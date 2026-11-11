// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * 备份读写的真机（Instrument）用例：这里读写的是真实沙箱文件，所以放在 src/ohosTest。
 * 备份格式、数据修复、还原决策这些纯逻辑用例在 src/test/BackupModel.test.ets，
 * 它们不需要设备；这个文件只补上必须有文件系统的部分。
 */

import { afterAll, beforeAll, describe, expect, it, TestType } from '@ohos/hypium';
import fs from '@ohos.file.fs';
import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import { readFullFile, writeTextFile } from '../../../main/ets/core/config/ConfigCommon';
import { ConfigRoot } from '../../../main/ets/core/config/Config';
import { ConfigManager } from '../../../main/ets/core/config/ConfigManager';
import {
    BackupIssueCode,
    BackupRestoreAction,
    CONSOLIDATED_BACKUP_FILE,
    CONNECTIONS_DIR,
    connectionConfigPath,
    decodeBackupEnvelope,
    fatalIssuesOf,
    GROUPS_FILE,
    hasIssueCode,
    IBackupAppVersion,
    SETTINGS_FILE
} from '../../../main/ets/core/backup/BackupModel';
import {
    exportBackupToUri,
    importBackupFromUri,
    listConfigFiles,
    readConfigSnapshot,
    restoreSystemBackup,
    writeConsolidatedBackup
} from '../../../main/ets/core/backup/BackupStore';

const OLD_APP: IBackupAppVersion = { code: 1, name: '0.0.1' };
const FUTURE_APP: IBackupAppVersion = { code: 99999999, name: '99.0.0' };
const TEST_NODE_NAME = 'it-backup-node';

let scratchDir = '';

function ensureDir(dir: string): void {
    try {
        fs.mkdirSync(dir, true);
    } catch (error) {
        // 13900015: already exists
        if (error.code !== 13900015) {
            throw error as Error;
        }
    }
}

function pathOf(relative: string): string {
    return scratchDir + '/' + relative;
}

function exists(relative: string): boolean {
    return fs.accessSync(pathOf(relative));
}

async function resetScratch(): Promise<void> {
    try {
        await fs.rmdir(scratchDir);
    } catch (error) {
        // 目录还不存在，直接建。
    }
    ensureDir(scratchDir);
}

async function writeFixture(relative: string, content: string): Promise<void> {
    const full = pathOf(relative);
    const slash = full.lastIndexOf('/');
    if (slash > scratchDir.length) {
        ensureDir(full.substring(0, slash));
    }
    await writeTextFile(content, full);
}

function groupsWithConnection(connectionId: string): string {
    return '{ "groups": [{ "id": "default", "name": "Default", "connections": ["' + connectionId + '"] }],' +
        ' "connections": [{ "id": "' + connectionId + '", "name": "node-a",' +
        ' "metadata": { "subscription": "https://example.test/sub" } }] }';
}

async function seedConfigDir(): Promise<void> {
    await writeFixture(GROUPS_FILE, groupsWithConnection('c1'));
    await writeFixture(SETTINGS_FILE, '{ "mtu": 1420 }');
    await writeFixture(connectionConfigPath('c1'), '{ "remarks": "node-a", "server": "example.test" }');
}

export default function backupStoreTest() {
    describe('backupStoreFileTest', () => {
        beforeAll((): void => {
            const context = abilityDelegatorRegistry.getAbilityDelegator()
                .getAppContext();
            scratchDir = context.filesDir + '/backup-it';
            ensureDir(scratchDir);
        });

        afterAll(async (): Promise<void> => {
            try {
                await fs.rmdir(scratchDir);
            } catch (error) {
                // 已经没了
            }
        });

        it('collects_the_real_config_files_and_ignores_the_snapshot', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();
                await seedConfigDir();
                await writeFixture(CONSOLIDATED_BACKUP_FILE, '{"not a config": true}');

                const files = await listConfigFiles(scratchDir);
                expect(files.length).assertEqual(3);
                let sawSnapshot = false;
                for (const file of files) {
                    if (file.path === CONSOLIDATED_BACKUP_FILE) {
                        sawSnapshot = true;
                    }
                }
                expect(sawSnapshot).assertFalse();

                const collected = await readConfigSnapshot(scratchDir);
                expect(fatalIssuesOf(collected.issues).length).assertEqual(0);
                expect(collected.snapshot.groups[0].id).assertEqual('default');
                const config = collected.snapshot.connections[0].config;
                expect(config !== undefined).assertTrue();
                if (config !== undefined) {
                    expect((config as Record<string, string>)['server']).assertEqual('example.test');
                }
                done();
            });

        it('writes_a_snapshot_that_the_same_build_can_read_back', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();
                await seedConfigDir();

                const written = await writeConsolidatedBackup(scratchDir);
                expect(fatalIssuesOf(written.issues).length).assertEqual(0);
                expect(exists(CONSOLIDATED_BACKUP_FILE)).assertTrue();

                const text = await readFullFile(pathOf(CONSOLIDATED_BACKUP_FILE));
                expect(text !== undefined).assertTrue();
                if (text === undefined) {
                    done();
                    return;
                }
                const envelope = decodeBackupEnvelope(text).envelope;
                expect(envelope !== undefined).assertTrue();
                if (envelope === undefined) {
                    done();
                    return;
                }
                expect(envelope.snapshot.groups.length).assertEqual(1);
                expect(envelope.snapshot.connections[0].name).assertEqual('node-a');
                done();
            });

        it('rebuilds_the_config_dir_from_the_snapshot_after_a_lost_groups_file', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();
                await seedConfigDir();
                await writeConsolidatedBackup(scratchDir);
                await fs.unlink(pathOf(GROUPS_FILE));
                expect(exists(GROUPS_FILE)).assertFalse();

                const outcome = await restoreSystemBackup(scratchDir, OLD_APP);
                expect(outcome.plan.action).assertEqual(BackupRestoreAction.Repair);
                expect(outcome.applied).assertTrue();
                expect(exists(GROUPS_FILE)).assertTrue();

                const restored = await readConfigSnapshot(scratchDir);
                expect(restored.snapshot.groups[0].connections[0]).assertEqual('c1');
                expect(restored.snapshot.connections[0].config !== undefined).assertTrue();
                done();
            });

        it('does_not_touch_files_when_the_data_came_from_a_newer_app', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();
                await seedConfigDir();
                await writeConsolidatedBackup(scratchDir);
                await fs.unlink(pathOf(GROUPS_FILE));

                const outcome = await restoreSystemBackup(scratchDir, FUTURE_APP);
                expect(outcome.plan.action).assertEqual(BackupRestoreAction.Keep);
                expect(outcome.applied).assertFalse();
                // 没重建，也没把快照当成配置留下。
                expect(exists(GROUPS_FILE)).assertFalse();
                done();
            });

        it('resets_a_config_dir_whose_restored_data_is_unusable', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();
                await writeFixture(GROUPS_FILE, 'this is not JSON');

                const outcome = await restoreSystemBackup(scratchDir, OLD_APP);
                expect(outcome.plan.action).assertEqual(BackupRestoreAction.Reset);
                expect(outcome.applied).assertTrue();
                expect(exists(GROUPS_FILE)).assertFalse();
                done();
            });

        it('reports_missing_and_orphan_connection_files_of_a_real_directory', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();
                await writeFixture(GROUPS_FILE,
                    '{ "groups": [{ "id": "default", "name": "Default", "connections": ["not-here"] }],' +
                    ' "connections": [{ "id": "gone", "name": "deleted-node" }] }');
                await writeFixture(connectionConfigPath('stray'), '{}');

                const collected = await readConfigSnapshot(scratchDir);
                expect(hasIssueCode(collected.issues, BackupIssueCode.UnknownConnection)).assertTrue();
                expect(hasIssueCode(collected.issues, BackupIssueCode.MissingConnectionConfig)).assertTrue();
                expect(hasIssueCode(collected.issues, BackupIssueCode.OrphanConnectionConfig)).assertTrue();
                expect(fatalIssuesOf(collected.issues).length).assertEqual(0);
                // 快照文件不算配置，这里只剩 groups.json 和那份没人引用的配置。
                expect((await listConfigFiles(scratchDir)).length).assertEqual(2);
                done();
            });

        it('leaves_the_previous_files_when_the_repair_cannot_be_written', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();
                await seedConfigDir();
                await writeConsolidatedBackup(scratchDir);

                // 把 connections/ 换成同名的普通文件：连接配置放不下。
                await fs.rmdir(pathOf(CONNECTIONS_DIR));
                await writeFixture(CONNECTIONS_DIR, 'not a directory');
                // 先确认前提真的成立，否则下面的断言会因为别的原因通过。
                expect(fs.statSync(pathOf(CONNECTIONS_DIR)).isFile()).assertTrue();
                const groupsBefore = await readFullFile(pathOf(GROUPS_FILE));
                expect(groupsBefore !== undefined).assertTrue();

                const outcome = await restoreSystemBackup(scratchDir, OLD_APP);
                expect(outcome.plan.action).assertEqual(BackupRestoreAction.Repair);
                expect(outcome.applied).assertFalse();
                // 放不下就不写：一份配置也不该被换掉。
                const groupsAfter = await readFullFile(pathOf(GROUPS_FILE));
                if (groupsBefore === undefined || groupsAfter === undefined) {
                    done();
                    return;
                }
                expect(groupsAfter).assertEqual(groupsBefore);
                expect(fs.statSync(pathOf(CONNECTIONS_DIR)).isFile()).assertTrue();
                done();
            });

        it('writes_nothing_when_the_config_dir_cannot_be_read', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await resetScratch();

                const collected = await writeConsolidatedBackup(scratchDir);
                expect(hasIssueCode(collected.issues, BackupIssueCode.NoGroupsFile)).assertTrue();
                expect(exists(CONSOLIDATED_BACKUP_FILE)).assertFalse();
                done();
            });
    });

    describe('configManagerRestoreTest', () => {
        let backupFilePath = '';

        beforeAll(async (): Promise<void> => {
            const context = abilityDelegatorRegistry.getAbilityDelegator()
                .getAppContext();
            scratchDir = context.filesDir + '/backup-it';
            ensureDir(scratchDir);
            await ConfigManager.loadConfigurations();
            await ConfigManager.saveConfigurations();
            backupFilePath = scratchDir + '/roundtrip.json';
        });

        afterAll(async (): Promise<void> => {
            // 别把用例建出来的连接留在设备上。
            const text = await readFullFile(backupFilePath);
            const envelope = text === undefined ? undefined : decodeBackupEnvelope(text).envelope;
            if (envelope !== undefined) {
                for (const connection of envelope.snapshot.connections) {
                    if (connection.name === TEST_NODE_NAME) {
                        await ConfigManager.removeConnection(connection.id);
                    }
                }
            }
            try {
                await fs.rmdir(scratchDir);
            } catch (error) {
                // 已经没了
            }
        });

        it('restores_a_removed_connection_through_a_backup_file', TestType.FUNCTION,
            async (done: Function): Promise<void> => {
                await ConfigManager.addConnectionToGroup(TEST_NODE_NAME, 'default', new ConfigRoot());

                const exported = await exportBackupToUri(backupFilePath);
                expect(exported.ok).assertTrue();
                expect(exported.connectionCount >= 1).assertTrue();
                expect(exported.groupCount >= 1).assertTrue();

                const text = await readFullFile(backupFilePath);
                expect(text !== undefined).assertTrue();
                if (text === undefined) {
                    done();
                    return;
                }
                const envelope = decodeBackupEnvelope(text).envelope;
                expect(envelope !== undefined).assertTrue();
                if (envelope === undefined) {
                    done();
                    return;
                }
                let connectionId = '';
                for (const connection of envelope.snapshot.connections) {
                    if (connection.name === TEST_NODE_NAME) {
                        connectionId = connection.id;
                    }
                }
                expect(connectionId.length > 0).assertTrue();

                // 先真的删掉，再靠备份找回来。
                expect(await ConfigManager.removeConnection(connectionId)).assertTrue();
                expect(ConfigManager.getConnection(connectionId) === undefined).assertTrue();

                const imported = await importBackupFromUri(backupFilePath);
                expect(imported.ok).assertTrue();
                expect(imported.connectionCount >= 1).assertTrue();

                const restored = ConfigManager.getConnection(connectionId);
                expect(restored !== undefined).assertTrue();
                if (restored !== undefined) {
                    expect(restored.name).assertEqual(TEST_NODE_NAME);
                }
                done();
            });
    });
}
