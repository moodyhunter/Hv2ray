// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * 备份格式、数据修复和还原决策的 Local Test 用例。
 *
 * 放在 src/test 而不是 src/ohosTest：BackupModel 不碰任何系统 API，这些用例不需要
 * 设备。真实读写配置目录的部分在 src/ohosTest/ets/test/BackupStore.test.ets。
 */

import { describe, expect, it, TestType } from '@ohos/hypium';
import {
    BACKUP_FORMAT,
    BackupIssueCode,
    BackupRestoreAction,
    collectBackupSnapshot,
    CONSOLIDATED_BACKUP_FILE,
    connectionConfigPath,
    connectionIdOfConfigPath,
    createBackupEnvelope,
    decodeBackupEnvelope,
    emptyBackupSnapshot,
    encodeBackupEnvelope,
    GROUPS_FILE,
    hasIssueCode,
    IBackupAppVersion,
    IBackupEnvelope,
    IBackupIssue,
    IBackupRestoreInput,
    IBackupSnapshot,
    parseSnapshotParts,
    planBackupRestore,
    renderBackupConfigFiles,
    SETTINGS_FILE,
    suggestBackupFileName
} from '../main/ets/core/backup/BackupModel';

function sampleSettings(): object {
    const settings: object = new Object();
    settings['mtu'] = 1420;
    return settings;
}

function sampleMetadata(): object {
    const metadata: object = new Object();
    metadata['subscription'] = 'https://example.test/sub';
    return metadata;
}

function sampleConfig(): object {
    const config: object = new Object();
    config['remarks'] = 'node-a';
    return config;
}

function sampleAppVersion(): IBackupAppVersion {
    return { code: 1000000, name: '1.0.0' };
}

function sampleSnapshot(): IBackupSnapshot {
    return {
        groups: [
            { id: 'default', name: 'Default', connections: ['c1'] },
            { id: 'subscription', name: 'Subscription', connections: [] }
        ],
        connections: [{ id: 'c1', name: 'node-a', metadata: sampleMetadata(), config: sampleConfig() }],
        settings: sampleSettings()
    };
}

function envelopeOf(snapshot: IBackupSnapshot): IBackupEnvelope {
    return createBackupEnvelope(snapshot, 1700000000000, sampleAppVersion());
}

function encodedSample(): string {
    return encodeBackupEnvelope(envelopeOf(sampleSnapshot()));
}

function groupsFileContent(groups: string, connections: string): string {
    return `{ "groups": ${groups}, "connections": ${connections} }`;
}

function planInput(envelope: IBackupEnvelope | undefined, issues: IBackupIssue[], sourceCode: number,
    groupsUsable: boolean): IBackupRestoreInput {
    return {
        sourceVersion: { code: sourceCode, name: 'source-version' },
        currentVersion: sampleAppVersion(),
        envelope: envelope,
        issues: issues,
        groupsUsable: groupsUsable
    };
}

export default function backupModelTest() {
    describe('backupFormatTest', () => {
        it('keeps_everything_across_an_envelope_round_trip', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope(encodedSample());

            expect(decoded.issues.length).assertEqual(0);
            const envelope = decoded.envelope;
            expect(envelope !== undefined).assertTrue();
            if (envelope === undefined) {
                return;
            }
            expect(envelope.format).assertEqual(BACKUP_FORMAT);
            expect(envelope.createdAt).assertEqual(1700000000000);
            expect(envelope.appVersion.code).assertEqual(1000000);
            expect(envelope.snapshot.groups.length).assertEqual(2);
            expect(envelope.snapshot.groups[0].connections[0]).assertEqual('c1');
            expect(envelope.snapshot.connections[0].name).assertEqual('node-a');
            // 不认识的字段也要原样带回来：备份不该丢用户数据。
            const metadata = envelope.snapshot.connections[0].metadata as Record<string, string>;
            expect(metadata['subscription']).assertEqual('https://example.test/sub');
            const settings = envelope.snapshot.settings as Record<string, number>;
            expect(settings['mtu']).assertEqual(1420);
            // 连接配置内联在 connections[] 里，解码后必须还在，
            // 否则还原时 renderBackupConfigFiles 会一份连接配置都不写。
            const config = envelope.snapshot.connections[0].config;
            expect(config !== undefined).assertTrue();
            if (config !== undefined) {
                expect((config as Record<string, string>)['remarks']).assertEqual('node-a');
            }
        });

        it('writes_the_connection_files_back_from_a_decoded_backup', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope(encodedSample());
            if (decoded.envelope === undefined) {
                return;
            }
            const files = renderBackupConfigFiles(decoded.envelope.snapshot);

            let rendered = '';
            for (const file of files) {
                if (file.path === connectionConfigPath('c1')) {
                    rendered = file.content;
                }
            }
            expect(rendered.length > 0).assertTrue();
            expect((JSON.parse(rendered) as Record<string, string>)['remarks']).assertEqual('node-a');
        });

        it('rejects_empty_and_broken_json', TestType.FUNCTION, (): void => {
            for (const text of ['', '   ', 'null', '{oops']) {
                const decoded = decodeBackupEnvelope(text);
                expect(decoded.envelope === undefined).assertTrue();
                expect(decoded.issues.length).assertEqual(1);
                expect(decoded.issues[0].code).assertEqual(BackupIssueCode.NotJson);
                expect(decoded.issues[0].fatal).assertTrue();
            }
        });

        it('rejects_a_json_file_that_is_not_a_backup', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope('{ "groups": [] }');
            expect(decoded.envelope === undefined).assertTrue();
            expect(decoded.issues[0].code).assertEqual(BackupIssueCode.NotABackup);
        });

        it('rejects_a_backup_without_a_version', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope(`{ "format": "${BACKUP_FORMAT}" }`);
            expect(decoded.envelope === undefined).assertTrue();
            expect(decoded.issues[0].code).assertEqual(BackupIssueCode.NotABackup);
        });

        it('rejects_formats_this_build_cannot_read', TestType.FUNCTION, (): void => {
            const tooNew = decodeBackupEnvelope(
                `{ "format": "${BACKUP_FORMAT}", "version": 99, "snapshot": {} }`);
            expect(tooNew.envelope === undefined).assertTrue();
            expect(tooNew.issues[0].code).assertEqual(BackupIssueCode.FormatTooNew);

            const tooOld = decodeBackupEnvelope(
                `{ "format": "${BACKUP_FORMAT}", "version": 0, "snapshot": {} }`);
            expect(tooOld.envelope === undefined).assertTrue();
            expect(tooOld.issues[0].code).assertEqual(BackupIssueCode.FormatTooOld);
        });

        it('rejects_a_backup_without_a_payload', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope(`{ "format": "${BACKUP_FORMAT}", "version": 1 }`);
            expect(decoded.envelope === undefined).assertTrue();
            expect(decoded.issues[0].code).assertEqual(BackupIssueCode.NoGroupsFile);
        });

        it('tolerates_a_payload_whose_parts_are_not_lists', TestType.FUNCTION, (): void => {
            // groups / connections 缺失或类型不对：只算提醒，不能抛异常。
            const missing = decodeBackupEnvelope(
                `{ "format": "${BACKUP_FORMAT}", "version": 1, "snapshot": { "nope": 1 } }`);
            expect(missing.envelope !== undefined).assertTrue();
            expect(missing.issues.length).assertEqual(0);
            if (missing.envelope !== undefined) {
                expect(missing.envelope.snapshot.groups.length).assertEqual(0);
            }

            const arrayPayload = decodeBackupEnvelope(
                `{ "format": "${BACKUP_FORMAT}", "version": 1, "snapshot": [1, 2, 3] }`);
            expect(arrayPayload.envelope !== undefined).assertTrue();
            if (arrayPayload.envelope !== undefined) {
                expect(arrayPayload.envelope.snapshot.connections.length).assertEqual(0);
            }
        });
    });

    describe('snapshotRepairTest', () => {
        it('drops_group_references_to_unknown_connections', TestType.FUNCTION, (): void => {
            const raw = JSON.parse(groupsFileContent(
                '[{ "id": "default", "name": "Default", "connections": ["ghost", "ghost"] }]', '[]')) as object;
            const issues: IBackupIssue[] = [];
            const snapshot = parseSnapshotParts(raw, issues);

            expect(snapshot.groups.length).assertEqual(1);
            expect(snapshot.groups[0].connections.length).assertEqual(0);
            expect(hasIssueCode(issues, BackupIssueCode.UnknownConnection)).assertTrue();
            expect(issues[0].fatal).assertFalse();
        });

        it('keeps_only_the_first_of_a_duplicated_entry', TestType.FUNCTION, (): void => {
            const raw = JSON.parse(groupsFileContent(
                '[{ "id": "a", "name": "first", "connections": [] },' +
                '  { "id": "a", "name": "second", "connections": [] },' +
                '  { "name": "no id", "connections": [] }]',
                '[{ "id": "c1", "name": "one" }, { "id": "c1", "name": "two" }]')) as object;
            const issues: IBackupIssue[] = [];
            const snapshot = parseSnapshotParts(raw, issues);

            expect(snapshot.groups.length).assertEqual(1);
            expect(snapshot.groups[0].name).assertEqual('first');
            expect(snapshot.connections.length).assertEqual(1);
            expect(snapshot.connections[0].name).assertEqual('one');
            expect(hasIssueCode(issues, BackupIssueCode.DuplicatedGroup)).assertTrue();
            expect(hasIssueCode(issues, BackupIssueCode.DuplicatedConnection)).assertTrue();
            expect(hasIssueCode(issues, BackupIssueCode.InvalidGroup)).assertTrue();
            for (const issue of issues) {
                expect(issue.fatal).assertFalse();
            }
        });

        it('tolerates_missing_lists_and_bad_field_types', TestType.FUNCTION, (): void => {
            const issues: IBackupIssue[] = [];
            const snapshot = parseSnapshotParts(JSON.parse('{ "groups": 1, "connections": "x" }') as object, issues);

            expect(snapshot.groups.length).assertEqual(0);
            expect(snapshot.connections.length).assertEqual(0);
            expect(issues.length).assertEqual(0);
            const settings = snapshot.settings as Record<string, number>;
            expect(settings['mtu'] === undefined).assertTrue();
        });

        it('drops_bad_members_inside_a_group', TestType.FUNCTION, (): void => {
            const raw = JSON.parse(groupsFileContent(
                '[{ "id": "a", "name": "A", "connections": ["c1", "", 7, "c1"] }]',
                '[{ "id": "c1", "name": "node-a" }]')) as object;
            const snapshot = parseSnapshotParts(raw, []);

            expect(snapshot.groups[0].connections.length).assertEqual(1);
            expect(snapshot.groups[0].connections[0]).assertEqual('c1');
        });

        it('starts_from_an_empty_snapshot', TestType.FUNCTION, (): void => {
            const snapshot = emptyBackupSnapshot();
            expect(snapshot.groups.length).assertEqual(0);
            expect(snapshot.connections.length).assertEqual(0);
        });
    });

    describe('configFileMappingTest', () => {
        it('renders_groups_settings_and_every_connection_config', TestType.FUNCTION, (): void => {
            const files = renderBackupConfigFiles(sampleSnapshot());

            expect(files.length).assertEqual(3);
            expect(files[0].path).assertEqual(GROUPS_FILE);
            expect(files[1].path).assertEqual(SETTINGS_FILE);
            expect(files[2].path).assertEqual('connections/c1.json');
            expect(files[2].path).assertEqual(connectionConfigPath('c1'));
        });

        it('does_not_write_a_config_file_for_a_connection_without_one', TestType.FUNCTION, (): void => {
            const snapshot = emptyBackupSnapshot();
            snapshot.groups.push({ id: 'default', name: 'Default', connections: ['c1'] });
            snapshot.connections.push({ id: 'c1', name: 'node-a', metadata: new Object() });

            expect(renderBackupConfigFiles(snapshot).length).assertEqual(2);
        });

        it('reads_back_what_it_rendered', TestType.FUNCTION, (): void => {
            const collected = collectBackupSnapshot(renderBackupConfigFiles(sampleSnapshot()));

            expect(collected.issues.length).assertEqual(0);
            expect(collected.snapshot.groups.length).assertEqual(2);
            expect(collected.snapshot.connections.length).assertEqual(1);
            const config = collected.snapshot.connections[0].config;
            expect(config !== undefined).assertTrue();
            if (config !== undefined) {
                expect((config as Record<string, string>)['remarks']).assertEqual('node-a');
            }
            const metadata = collected.snapshot.connections[0].metadata as Record<string, string>;
            expect(metadata['subscription']).assertEqual('https://example.test/sub');
        });

        it('reports_a_missing_groups_file_as_fatal', TestType.FUNCTION, (): void => {
            const collected = collectBackupSnapshot([]);

            expect(hasIssueCode(collected.issues, BackupIssueCode.NoGroupsFile)).assertTrue();
            expect(collected.issues[0].fatal).assertTrue();
            expect(collected.snapshot.groups.length).assertEqual(0);
        });

        it('survives_unparsable_groups_or_settings', TestType.FUNCTION, (): void => {
            const brokenGroups = collectBackupSnapshot([
                { path: GROUPS_FILE, content: 'not json at all' },
                { path: SETTINGS_FILE, content: 'also not json' }
            ]);
            expect(hasIssueCode(brokenGroups.issues, BackupIssueCode.NoGroupsFile)).assertTrue();
            expect(brokenGroups.snapshot.groups.length).assertEqual(0);

            const goodGroups = collectBackupSnapshot([
                {
                    path: GROUPS_FILE,
                    content: groupsFileContent('[{ "id": "a", "name": "A", "connections": [] }]', '[]')
                },
                { path: SETTINGS_FILE, content: '{ broken' }
            ]);
            expect(hasIssueCode(goodGroups.issues, BackupIssueCode.NotJson)).assertTrue();
            expect(goodGroups.snapshot.groups.length).assertEqual(1);
            for (const issue of goodGroups.issues) {
                expect(issue.fatal).assertFalse();
            }
        });

        it('flags_missing_and_orphan_connection_config_files', TestType.FUNCTION, (): void => {
            const collected = collectBackupSnapshot([
                {
                    path: GROUPS_FILE,
                    content: groupsFileContent('[{ "id": "a", "name": "A", "connections": ["c1"] }]',
                        '[{ "id": "c1", "name": "node-a" }]')
                },
                { path: 'connections/zombie.json', content: '{}' }
            ]);

            expect(hasIssueCode(collected.issues, BackupIssueCode.MissingConnectionConfig)).assertTrue();
            expect(hasIssueCode(collected.issues, BackupIssueCode.OrphanConnectionConfig)).assertTrue();
            expect(collected.snapshot.connections[0].config === undefined).assertTrue();
            for (const issue of collected.issues) {
                expect(issue.fatal).assertFalse();
            }
        });

        it('reports_an_unparsable_connection_config', TestType.FUNCTION, (): void => {
            const collected = collectBackupSnapshot([
                {
                    path: GROUPS_FILE,
                    content: groupsFileContent('[{ "id": "a", "name": "A", "connections": ["c1"] }]',
                        '[{ "id": "c1", "name": "node-a" }]')
                },
                { path: connectionConfigPath('c1'), content: 'garbage' }
            ]);

            expect(hasIssueCode(collected.issues, BackupIssueCode.MissingConnectionConfig)).assertTrue();
            expect(collected.snapshot.connections[0].config === undefined).assertTrue();
        });

        it('ignores_an_inline_config_left_in_the_groups_file', TestType.FUNCTION, (): void => {
            // 上一次还原会在 groups.json 里内联一份 config；独立文件不在就不能拿它当真。
            const collected = collectBackupSnapshot([
                {
                    path: GROUPS_FILE,
                    content: '{ "groups": [{ "id": "a", "name": "A", "connections": ["c1"] }],' +
                        ' "connections": [{ "id": "c1", "name": "node-a", "metadata": {},' +
                        '   "config": { "remarks": "left over from a restore" } }] }'
                }
            ]);

            expect(hasIssueCode(collected.issues, BackupIssueCode.MissingConnectionConfig)).assertTrue();
            expect(collected.snapshot.connections[0].config === undefined).assertTrue();
        });

        it('maps_only_real_connection_config_paths', TestType.FUNCTION, (): void => {
            expect(connectionIdOfConfigPath(GROUPS_FILE) === undefined).assertTrue();
            expect(connectionIdOfConfigPath(CONSOLIDATED_BACKUP_FILE) === undefined).assertTrue();
            expect(connectionIdOfConfigPath('connections/x.txt') === undefined).assertTrue();
            expect(connectionIdOfConfigPath('connections/') === undefined).assertTrue();
            expect(connectionIdOfConfigPath('connections/deep/nested.json') === undefined).assertTrue();
            expect(connectionIdOfConfigPath('connections/c1.json')).assertEqual('c1');
        });
    });

    describe('systemRestorePlanTest', () => {
        it('repairs_from_a_usable_snapshot', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope(encodedSample());
            if (decoded.envelope === undefined) {
                return;
            }
            const plan = planBackupRestore(planInput(decoded.envelope, decoded.issues, 1000000, true));
            expect(plan.action).assertEqual(BackupRestoreAction.Repair);
        });

        it('leaves_data_from_a_newer_app_alone', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope(encodedSample());
            if (decoded.envelope === undefined) {
                return;
            }
            // 数据来自更新的版本：别拿旧版本的序列化器去重写它。
            const plan = planBackupRestore(planInput(decoded.envelope, decoded.issues, 9999999, true));
            expect(plan.action).assertEqual(BackupRestoreAction.Keep);
        });

        it('keeps_restored_files_when_the_snapshot_is_unusable', TestType.FUNCTION, (): void => {
            const decoded = decodeBackupEnvelope(`{ "format": "${BACKUP_FORMAT}", "version": 99 }`);
            const plan = planBackupRestore(planInput(decoded.envelope, decoded.issues, 1000000, true));
            expect(plan.action).assertEqual(BackupRestoreAction.Keep);
        });

        it('resets_only_when_nothing_restored_is_usable', TestType.FUNCTION, (): void => {
            const withoutSnapshot = planBackupRestore(planInput(undefined, [], 1000000, false));
            expect(withoutSnapshot.action).assertEqual(BackupRestoreAction.Reset);

            const broken = decodeBackupEnvelope('{ "not": "a backup" }');
            const withBrokenSnapshot = planBackupRestore(planInput(broken.envelope, broken.issues, 1000000, false));
            expect(withBrokenSnapshot.action).assertEqual(BackupRestoreAction.Reset);
            expect(withBrokenSnapshot.reason).assertEqual(broken.issues[0].detail);
        });
    });

    describe('backupFileNameTest', () => {
        it('suggests_a_name_that_sorts_by_export_time', TestType.FUNCTION, (): void => {
            // hv2ray-backup-YYYYMMDD-HHMM.json
            const name = suggestBackupFileName(1700000000000);
            expect(name.startsWith('hv2ray-backup-')).assertTrue();
            expect(name.endsWith('.json')).assertTrue();
            expect(name.length).assertEqual(32);
            expect(name.charAt(22)).assertEqual('-');
        });
    });
}
