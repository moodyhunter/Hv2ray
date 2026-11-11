// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * 备份/还原的文件结构与全部纯逻辑。
 *
 * 这个文件刻意不 import 任何系统 API（fs / hilog / application / BuildProfile）：
 * - Local Test 不支持系统 API，纯逻辑才能在 PC 上直接跑用例；
 * - 应用内的导出导入和系统级 BackupExtensionAbility 共用同一套格式、校验与决策规则。
 * 读写文件的部分在 core/backup/BackupStore.ets，它只搬运这里定义的数据。
 */

/** 每个备份文件里的格式标识，用来拒绝其它来源的 JSON。 */
export const BACKUP_FORMAT = 'hv2ray-backup';
/** 本版本理解的备份格式版本。 */
export const BACKUP_FORMAT_VERSION = 1;
/** 仍然能读的最老格式版本。 */
export const BACKUP_MIN_SUPPORTED_VERSION = 1;

/** 配置目录内那份自带版本信息的合并快照名；系统备份以它为准。 */
export const CONSOLIDATED_BACKUP_FILE = 'backup.json';
/** 运行期配置文件名，备份里的相对路径与之一致。 */
export const GROUPS_FILE = 'groups.json';
export const SETTINGS_FILE = 'settings.json';
export const CONNECTIONS_DIR = 'connections';
/** 备份文件的扩展名。 */
export const BACKUP_FILE_SUFFIX = '.json';

export interface IBackupAppVersion {
    code: number;
    name: string;
}

export interface IBackupGroup {
    id: string;
    name: string;
    connections: string[];
}

export interface IBackupConnection {
    id: string;
    name: string;
    /** groups.json 里该连接的 metadata 原样保留，未知字段不丢。 */
    metadata: object;
    /** connections/<id>.json 的内容；没有对应文件时该字段缺失。 */
    config?: object;
}

export interface IBackupSnapshot {
    groups: IBackupGroup[];
    connections: IBackupConnection[];
    /** settings.json 的内容，原样搬运。 */
    settings: object;
}

export interface IBackupEnvelope {
    format: string;
    version: number;
    createdAt: number;
    appVersion: IBackupAppVersion;
    snapshot: IBackupSnapshot;
}

/** 一个待写入/刚读出的配置文件，path 相对配置目录。 */
export interface IBackupFileEntry {
    path: string;
    content: string;
}

export enum BackupIssueCode {
    NotJson = 'not_json',
    NotABackup = 'not_backup',
    FormatTooNew = 'format_too_new',
    FormatTooOld = 'format_too_old',
    NoGroupsFile = 'no_groups_file',
    InvalidGroup = 'invalid_group',
    DuplicatedGroup = 'duplicated_group',
    DuplicatedConnection = 'duplicated_connection',
    UnknownConnection = 'unknown_connection',
    MissingConnectionConfig = 'missing_connection_config',
    OrphanConnectionConfig = 'orphan_connection_config'
}

export interface IBackupIssue {
    code: BackupIssueCode;
    detail: string;
    /** true 表示这份数据不能用，只能保持原状或重来；false 只是提醒。 */
    fatal: boolean;
}

export interface IBackupDecodeResult {
    envelope: IBackupEnvelope | undefined;
    issues: IBackupIssue[];
}

export interface IBackupCollectResult {
    snapshot: IBackupSnapshot;
    issues: IBackupIssue[];
}

export enum BackupRestoreAction {
    /** 用合并快照重写配置文件。 */
    Repair = 'repair',
    /** 什么都不做，保留已恢复的文件。 */
    Keep = 'keep',
    /** 恢复出来的数据不可用，删掉它让应用重建默认配置。 */
    Reset = 'reset'
}

export interface IBackupRestoreInput {
    /** 备份数据来自哪个应用版本（BackupExtensionAbility 给的 BundleVersion）。 */
    sourceVersion: IBackupAppVersion;
    currentVersion: IBackupAppVersion;
    envelope: IBackupEnvelope | undefined;
    issues: IBackupIssue[];
    /** 恢复出来的 groups.json 本身是否可用。 */
    groupsUsable: boolean;
}

export interface IBackupRestorePlan {
    action: BackupRestoreAction;
    reason: string;
}

export function makeBackupIssue(code: BackupIssueCode, detail: string, fatal: boolean): IBackupIssue {
    return { code: code, detail: detail, fatal: fatal };
}

export function fatalIssuesOf(issues: IBackupIssue[]): IBackupIssue[] {
    return issues.filter((issue: IBackupIssue): boolean => issue.fatal);
}

export function hasIssueCode(issues: IBackupIssue[], code: BackupIssueCode): boolean {
    return issues.findIndex((issue: IBackupIssue): boolean => issue.code === code) >= 0;
}

export function emptyBackupSnapshot(): IBackupSnapshot {
    const snapshot: IBackupSnapshot = { groups: [], connections: [], settings: new Object() };
    return snapshot;
}

export function createBackupEnvelope(snapshot: IBackupSnapshot, createdAt: number,
    appVersion: IBackupAppVersion): IBackupEnvelope {
    return {
        format: BACKUP_FORMAT,
        version: BACKUP_FORMAT_VERSION,
        createdAt: createdAt,
        appVersion: appVersion,
        snapshot: snapshot
    };
}

export function encodeBackupEnvelope(envelope: IBackupEnvelope): string {
    return JSON.stringify(envelope, undefined, 2);
}

/** 解析并校验一份备份文件。不可用的数据返回 fatal issue，而不是半成品。 */
export function decodeBackupEnvelope(text: string): IBackupDecodeResult {
    const trimmed = text.trim();
    if (trimmed.length === 0 || trimmed === 'null') {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.NotJson, 'the backup file is empty', true)]
        };
    }

    let raw: object;
    try {
        raw = JSON.parse(trimmed);
    } catch (error) {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.NotJson, 'the backup file is not valid JSON', true)]
        };
    }

    if (readStringField(raw, 'format') !== BACKUP_FORMAT) {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.NotABackup, 'not a Hv2ray backup file', true)]
        };
    }

    const versionField = asField(raw, 'version');
    if (typeof versionField !== 'number') {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.NotABackup, 'the backup file has no format version', true)]
        };
    }
    const version = versionField as number;
    if (version > BACKUP_FORMAT_VERSION) {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.FormatTooNew,
                `backup format ${version} is newer than ${BACKUP_FORMAT_VERSION}`, true)]
        };
    }
    if (version < BACKUP_MIN_SUPPORTED_VERSION) {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.FormatTooOld,
                `backup format ${version} is older than ${BACKUP_MIN_SUPPORTED_VERSION}`, true)]
        };
    }

    const issues: IBackupIssue[] = [];
    const snapshotRaw = asField(raw, 'snapshot');
    if (typeof snapshotRaw !== 'object') {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.NoGroupsFile, 'the backup file has no payload', true)]
        };
    }

    let snapshot: IBackupSnapshot;
    try {
        snapshot = parseSnapshotParts(snapshotRaw as object, issues);
    } catch (error) {
        return {
            envelope: undefined,
            issues: [makeBackupIssue(BackupIssueCode.NotABackup, 'the backup payload cannot be read', true)]
        };
    }

    const envelope: IBackupEnvelope = {
        format: BACKUP_FORMAT,
        version: version,
        createdAt: readNumberField(raw, 'createdAt'),
        appVersion: readAppVersion(asField(raw, 'appVersion')),
        snapshot: snapshot
    };
    return { envelope: envelope, issues: issues };
}

/**
 * 解析 { groups, connections } 这一层。groups.json 的顶层形状和备份信封里的
 * snapshot 用的就是同一层，所以两条路径共用这个函数。
 */
export function parseSnapshotParts(raw: object, issues: IBackupIssue[]): IBackupSnapshot {
    const snapshot = emptyBackupSnapshot();

    const groupList = asField(raw, 'groups') as object[];
    const seenGroups = new Map<string, boolean>();
    if (typeof groupList === 'object') {
        for (let i = 0; i < groupList.length; i++) {
            const item = groupList[i] as object;
            const id = readStringField(item, 'id');
            if (id.length === 0) {
                issues.push(makeBackupIssue(BackupIssueCode.InvalidGroup, `group #${i} has no id`, false));
                continue;
            }
            if (seenGroups.get(id) !== undefined) {
                issues.push(makeBackupIssue(BackupIssueCode.DuplicatedGroup, `duplicated group ${id}`, false));
                continue;
            }
            seenGroups.set(id, true);
            const members: string[] = [];
            const referenced = asField(item, 'connections') as string[];
            if (typeof referenced === 'object') {
                for (let j = 0; j < referenced.length; j++) {
                    const connId = referenced[j];
                    if (typeof connId === 'string' && connId.length > 0 && members.indexOf(connId) < 0) {
                        members.push(connId);
                    }
                }
            }
            snapshot.groups.push({ id: id, name: readStringField(item, 'name'), connections: members });
        }
    }

    const connectionList = asField(raw, 'connections') as object[];
    const seenConnections = new Map<string, boolean>();
    if (typeof connectionList === 'object') {
        for (let i = 0; i < connectionList.length; i++) {
            const item = connectionList[i] as object;
            const id = readStringField(item, 'id');
            if (id.length === 0) {
                issues.push(makeBackupIssue(BackupIssueCode.InvalidGroup, `connection #${i} has no id`, false));
                continue;
            }
            if (seenConnections.get(id) !== undefined) {
                issues.push(makeBackupIssue(BackupIssueCode.DuplicatedConnection,
                    `duplicated connection ${id}`, false));
                continue;
            }
            seenConnections.set(id, true);
            const metadataRaw = asField(item, 'metadata');
            snapshot.connections.push({
                id: id,
                name: readStringField(item, 'name'),
                metadata: typeof metadataRaw === 'object' ? metadataRaw as object : new Object()
            });
        }
    }

    // 分组引用了不存在的连接：去掉这个引用，其余数据照旧可用。
    const knownIds = new Map<string, boolean>();
    for (const connection of snapshot.connections) {
        knownIds.set(connection.id, true);
    }
    for (const group of snapshot.groups) {
        const kept: string[] = [];
        for (const connId of group.connections) {
            if (knownIds.get(connId) !== undefined) {
                kept.push(connId);
            } else {
                issues.push(makeBackupIssue(BackupIssueCode.UnknownConnection,
                    `group ${group.id} references unknown connection ${connId}`, false));
            }
        }
        group.connections = kept;
    }

    const settingsRaw = asField(raw, 'settings');
    snapshot.settings = typeof settingsRaw === 'object' ? settingsRaw as object : new Object();
    return snapshot;
}

/** 把快照摊平成配置目录里的文件。config 缺失的连接不写文件。 */
export function renderBackupConfigFiles(snapshot: IBackupSnapshot): IBackupFileEntry[] {
    const files: IBackupFileEntry[] = [];

    const root: object = new Object();
    root['groups'] = snapshot.groups;
    root['connections'] = snapshot.connections;
    files.push({ path: GROUPS_FILE, content: JSON.stringify(root, undefined, 2) });
    files.push({ path: SETTINGS_FILE, content: JSON.stringify(snapshot.settings, undefined, 2) });

    for (const connection of snapshot.connections) {
        const config = connection.config;
        if (config !== undefined) {
            files.push({ path: connectionConfigPath(connection.id), content: JSON.stringify(config, undefined, 2) });
        }
    }
    return files;
}

/** 反向：把配置目录里的文件收成快照。单个文件读不动只产生 issue，不影响其余数据。 */
export function collectBackupSnapshot(files: IBackupFileEntry[]): IBackupCollectResult {
    const issues: IBackupIssue[] = [];
    let snapshot = emptyBackupSnapshot();

    const groupsFile = findFileEntry(files, GROUPS_FILE);
    if (groupsFile === undefined) {
        issues.push(makeBackupIssue(BackupIssueCode.NoGroupsFile, `no ${GROUPS_FILE} to read from`, true));
    } else {
        try {
            snapshot = parseSnapshotParts(JSON.parse(groupsFile.content) as object, issues);
        } catch (error) {
            issues.push(makeBackupIssue(BackupIssueCode.NoGroupsFile, `${GROUPS_FILE} is not valid JSON`, true));
        }
    }

    const settingsFile = findFileEntry(files, SETTINGS_FILE);
    if (settingsFile !== undefined) {
        try {
            snapshot.settings = JSON.parse(settingsFile.content) as object;
        } catch (error) {
            issues.push(makeBackupIssue(BackupIssueCode.NotJson, `${SETTINGS_FILE} is not valid JSON`, false));
        }
    }

    const knownIds = new Map<string, boolean>();
    for (const connection of snapshot.connections) {
        knownIds.set(connection.id, true);
    }
    for (const file of files) {
        const connId = connectionIdOfConfigPath(file.path);
        if (connId === undefined) {
            continue;
        }
        if (knownIds.get(connId) === undefined) {
            issues.push(makeBackupIssue(BackupIssueCode.OrphanConnectionConfig,
                `${file.path} is not referenced by ${GROUPS_FILE}`, false));
        }
    }

    for (const connection of snapshot.connections) {
        const configFile = findFileEntry(files, connectionConfigPath(connection.id));
        if (configFile === undefined) {
            issues.push(makeBackupIssue(BackupIssueCode.MissingConnectionConfig,
                `connection ${connection.id} has no configuration file`, false));
            continue;
        }
        try {
            connection.config = JSON.parse(configFile.content) as object;
        } catch (error) {
            issues.push(makeBackupIssue(BackupIssueCode.MissingConnectionConfig,
                `the configuration file of ${connection.id} is not valid JSON`, false));
        }
    }

    return { snapshot: snapshot, issues: issues };
}

/**
 * 系统还原后的处理决策。原则是：能修就修，拿不准就不动用户的数据，
 * 只有恢复出来的东西确实不可用才推倒重来。
 */
export function planBackupRestore(input: IBackupRestoreInput): IBackupRestorePlan {
    if (input.sourceVersion.code > input.currentVersion.code) {
        return {
            action: BackupRestoreAction.Keep,
            reason: `data comes from ${input.sourceVersion.name} (${input.sourceVersion.code}), ` +
                `newer than this build (${input.currentVersion.code})`
        };
    }

    const fatal = fatalIssuesOf(input.issues);
    if (input.envelope === undefined || fatal.length > 0) {
        if (input.groupsUsable) {
            return { action: BackupRestoreAction.Keep, reason: 'the restored configuration files are usable' };
        }
        return {
            action: BackupRestoreAction.Reset,
            reason: fatal.length > 0 ? fatal[0].detail : 'no consolidated snapshot to repair from'
        };
    }

    return { action: BackupRestoreAction.Repair, reason: `rebuilding from ${CONSOLIDATED_BACKUP_FILE}` };
}

/** 备份文件名带上导出时间，方便在文件管理器里区分。 */
export function suggestBackupFileName(createdAt: number): string {
    const date = new Date(createdAt);
    const pad = (value: number): string => `${value < 10 ? '0' : ''}${value}`;
    return `hv2ray-backup-${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}` +
        `-${pad(date.getHours())}${pad(date.getMinutes())}${BACKUP_FILE_SUFFIX}`;
}

export function connectionConfigPath(connId: string): string {
    return CONNECTIONS_DIR + '/' + connId + BACKUP_FILE_SUFFIX;
}

/** 属于 connections/ 下的配置文件时返回连接 id，否则 undefined。 */
export function connectionIdOfConfigPath(path: string): string | undefined {
    const prefix = CONNECTIONS_DIR + '/';
    if (!path.startsWith(prefix) || !path.endsWith(BACKUP_FILE_SUFFIX)) {
        return undefined;
    }
    const connId = path.substring(prefix.length, path.length - BACKUP_FILE_SUFFIX.length);
    return connId.length === 0 || connId.indexOf('/') >= 0 ? undefined : connId;
}

function findFileEntry(files: IBackupFileEntry[], path: string): IBackupFileEntry | undefined {
    for (const file of files) {
        if (file.path === path) {
            return file;
        }
    }
    return undefined;
}

function readAppVersion(raw: Object | undefined): IBackupAppVersion {
    if (typeof raw !== 'object') {
        return { code: 0, name: '' };
    }
    const value = raw as object;
    return { code: readNumberField(value, 'code'), name: readStringField(value, 'name') };
}

/** 动态字段访问集中在这里：其它地方拿到的一定是具体类型。 */
function asField(raw: object, key: string): Object | undefined {
    return (raw as Record<string, Object | undefined>)[key];
}

function readStringField(raw: object, key: string): string {
    const value = asField(raw, key);
    return typeof value === 'string' ? value as string : '';
}

function readNumberField(raw: object, key: string): number {
    const value = asField(raw, key);
    return typeof value === 'number' ? value as number : 0;
}
