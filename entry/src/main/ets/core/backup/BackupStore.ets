// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * 备份/还原里唯一碰文件系统的部分：读配置目录、写配置目录、读写备份文件。
 * 格式、校验和决策逻辑都在 core/backup/BackupModel.ets，这里只搬运数据。
 *
 * 两条入口共用这里的函数：
 * - 应用内导出/导入：Settings 页选一个文件，exportBackupToUri / importBackupFromUri。
 * - 系统级备份还原：EntryBackupAbility 在 onBackup/onRestore 里调用
 *   writeConsolidatedBackup / restoreSystemBackup，配置目录里留一份 backup.json。
 */

import fs from '@ohos.file.fs';
import { VERSION_CODE, VERSION_NAME } from 'BuildProfile';
import Logger from '../../utils/Logging';
import { readFullFile, writeTextFile } from '../config/ConfigCommon';
import { ConfigManager } from '../config/ConfigManager';
import {
    BACKUP_FILE_SUFFIX,
    BackupIssueCode,
    BackupRestoreAction,
    collectBackupSnapshot,
    CONSOLIDATED_BACKUP_FILE,
    CONNECTIONS_DIR,
    connectionConfigPath,
    createBackupEnvelope,
    decodeBackupEnvelope,
    encodeBackupEnvelope,
    fatalIssuesOf,
    GROUPS_FILE,
    IBackupAppVersion,
    IBackupCollectResult,
    IBackupDecodeResult,
    IBackupFileEntry,
    IBackupIssue,
    IBackupRestoreInput,
    IBackupRestorePlan,
    IBackupSnapshot,
    makeBackupIssue,
    parseSnapshotParts,
    planBackupRestore,
    renderBackupConfigFiles,
    SETTINGS_FILE
} from './BackupModel';

const TAG = 'backup/BackupStore';

const ERR_FILE_NOT_EXISTS = 13900002;
const ERR_DIR_ALREADY_EXISTS = 13900015;

export interface IBackupRunResult {
    ok: boolean;
    groupCount: number;
    connectionCount: number;
    /** 问题原样带出来：UI 按 code 取本地文案，日志按 detail 排查。 */
    issues: IBackupIssue[];
    reason: string;
}

export interface ISystemRestoreOutcome {
    plan: IBackupRestorePlan;
    applied: boolean;
    issues: IBackupIssue[];
}

function currentAppVersion(): IBackupAppVersion {
    return { code: VERSION_CODE, name: VERSION_NAME };
}

function failedRunResult(reason: string, issues: IBackupIssue[]): IBackupRunResult {
    return { ok: false, groupCount: 0, connectionCount: 0, issues: issues, reason: reason };
}

function succeededRunResult(snapshot: IBackupSnapshot, reason: string, issues: IBackupIssue[]): IBackupRunResult {
    return {
        ok: true,
        groupCount: snapshot.groups.length,
        connectionCount: snapshot.connections.length,
        issues: issues,
        reason: reason
    };
}

function joinPath(dir: string, name: string): string {
    return dir + '/' + name;
}

/** 只有确认这里真的是目录才开始写文件，否则一个同名普通文件会让写出一半的配置。 */
function safeMkdir(dir: string): boolean {
    try {
        fs.mkdirSync(dir, true);
    } catch (error) {
        if (error.code !== ERR_DIR_ALREADY_EXISTS) {
            Logger.Error(TAG, `failed to create ${dir}: ${JSON.stringify(error)}`);
            return false;
        }
    }
    try {
        if (fs.statSync(dir).isDirectory()) {
            return true;
        }
    } catch (error) {
        Logger.Error(TAG, `cannot stat ${dir}: ${JSON.stringify(error)}`);
        return false;
    }
    Logger.Error(TAG, `${dir} exists but is not a directory`);
    return false;
}

/** 目录不存在时按空列表处理，其它错误记日志。 */
async function listFileNames(dir: string): Promise<string[]> {
    try {
        return await fs.listFile(dir);
    } catch (error) {
        if (error.code !== ERR_FILE_NOT_EXISTS) {
            Logger.Error(TAG, `failed to list ${dir}: ${JSON.stringify(error)}`);
        }
        return [];
    }
}

async function removeQuiet(path: string): Promise<void> {
    try {
        await fs.unlink(path);
    } catch (error) {
        if (error.code !== ERR_FILE_NOT_EXISTS) {
            Logger.Error(TAG, `failed to remove ${path}: ${JSON.stringify(error)}`);
        }
    }
}

/**
 * 列出配置目录里的配置文件，path 以配置目录为根。
 * backup.json 是这里的产物，不参与收集，否则快照会被当成一份配置。
 */
export async function listConfigFiles(baseDir: string): Promise<IBackupFileEntry[]> {
    const files: IBackupFileEntry[] = [];

    for (const name of await listFileNames(baseDir)) {
        if (name !== GROUPS_FILE && name !== SETTINGS_FILE) {
            continue;
        }
        const content = await readFullFile(joinPath(baseDir, name));
        if (content !== undefined) {
            files.push({ path: name, content: content });
        }
    }

    for (const name of await listFileNames(joinPath(baseDir, CONNECTIONS_DIR))) {
        if (!name.endsWith(BACKUP_FILE_SUFFIX)) {
            continue;
        }
        const id = name.substring(0, name.length - BACKUP_FILE_SUFFIX.length);
        const path = connectionConfigPath(id);
        const content = await readFullFile(joinPath(baseDir, path));
        if (content !== undefined) {
            files.push({ path: path, content: content });
        }
    }

    return files;
}

/** 读配置目录并收成快照；读不动的单个文件只产生 issue，不影响其它数据。 */
export async function readConfigSnapshot(baseDir: string): Promise<IBackupCollectResult> {
    const files = await listConfigFiles(baseDir);
    return collectBackupSnapshot(files);
}

async function writeConfigFilesToDir(baseDir: string, files: IBackupFileEntry[]): Promise<boolean> {
    if (!safeMkdir(baseDir) || !safeMkdir(joinPath(baseDir, CONNECTIONS_DIR))) {
        return false;
    }

    for (const file of files) {
        if (!await writeTextFile(file.content, joinPath(baseDir, file.path))) {
            return false;
        }
    }
    return true;
}

/**
 * 系统备份前调用：把配置目录压成一份带版本号的 backup.json。
 * 读不出可用数据时删掉旧快照，免得还原时用坏快照去盖掉还好的数据。
 */
export async function writeConsolidatedBackup(baseDir: string): Promise<IBackupCollectResult> {
    const collected = await readConfigSnapshot(baseDir);
    const fatal = fatalIssuesOf(collected.issues);
    if (fatal.length > 0) {
        Logger.Error(TAG, `not writing ${CONSOLIDATED_BACKUP_FILE}: ${fatal[0].detail}`);
        await removeQuiet(joinPath(baseDir, CONSOLIDATED_BACKUP_FILE));
        return collected;
    }

    const envelope = createBackupEnvelope(collected.snapshot, Date.now(), currentAppVersion());
    if (!await writeTextFile(encodeBackupEnvelope(envelope), joinPath(baseDir, CONSOLIDATED_BACKUP_FILE))) {
        collected.issues.push(makeBackupIssue(BackupIssueCode.NotABackup,
            `failed to write ${CONSOLIDATED_BACKUP_FILE}`, true));
    }
    return collected;
}

async function readConsolidatedBackup(baseDir: string): Promise<IBackupDecodeResult> {
    const text = await readFullFile(joinPath(baseDir, CONSOLIDATED_BACKUP_FILE));
    if (text === undefined) {
        return { envelope: undefined, issues: [] };
    }
    return decodeBackupEnvelope(text);
}

/** groups.json 自己是否可用，决定还原失败时是保留现状还是推倒重来。 */
async function isGroupsFileUsable(baseDir: string): Promise<boolean> {
    const text = await readFullFile(joinPath(baseDir, GROUPS_FILE));
    if (text === undefined) {
        return false;
    }
    try {
        const snapshot = parseSnapshotParts(JSON.parse(text) as object, []);
        return snapshot.groups.length > 0;
    } catch (error) {
        return false;
    }
}

/**
 * 系统还原后调用。文件由备份恢复框架解压到原路径，这里只判断
 * "还原出来的数据是否自洽"，不自洽时才动用户的数据。
 */
export async function restoreSystemBackup(baseDir: string,
    sourceVersion: IBackupAppVersion): Promise<ISystemRestoreOutcome> {
    const decoded = await readConsolidatedBackup(baseDir);
    const groupsUsable = await isGroupsFileUsable(baseDir);
    const input: IBackupRestoreInput = {
        sourceVersion: sourceVersion,
        currentVersion: currentAppVersion(),
        envelope: decoded.envelope,
        issues: decoded.issues,
        groupsUsable: groupsUsable
    };
    const plan = planBackupRestore(input);
    Logger.Info(TAG, `system restore: ${plan.action} (${plan.reason})`);

    if (plan.action === BackupRestoreAction.Keep) {
        return { plan: plan, applied: false, issues: decoded.issues };
    }

    if (plan.action === BackupRestoreAction.Reset) {
        // 恢复出来的配置不可用：删掉入口文件，应用下次启动时重建默认配置。
        await removeQuiet(joinPath(baseDir, GROUPS_FILE));
        await removeQuiet(joinPath(baseDir, CONSOLIDATED_BACKUP_FILE));
        return { plan: plan, applied: true, issues: decoded.issues };
    }

    const envelope = decoded.envelope;
    if (envelope === undefined) {
        return { plan: plan, applied: false, issues: decoded.issues };
    }
    if (!await writeConfigFilesToDir(baseDir, renderBackupConfigFiles(envelope.snapshot))) {
        return { plan: plan, applied: false, issues: decoded.issues };
    }
    Logger.Info(TAG, `repaired ${envelope.snapshot.groups.length} group(s) from ${CONSOLIDATED_BACKUP_FILE}`);
    return { plan: plan, applied: true, issues: decoded.issues };
}

/** 应用内"备份"：把当前配置写进用户选的备份文件。 */
export async function exportBackupToUri(uri: string): Promise<IBackupRunResult> {
    const collected = await readConfigSnapshot(ConfigManager.configDirPath);
    const fatal = fatalIssuesOf(collected.issues);
    if (fatal.length > 0) {
        Logger.Error(TAG, `refusing to export: ${fatal[0].detail}`);
        return failedRunResult(fatal[0].detail, collected.issues);
    }

    const envelope = createBackupEnvelope(collected.snapshot, Date.now(), currentAppVersion());
    if (!await writeTextFile(encodeBackupEnvelope(envelope), uri)) {
        return failedRunResult(`failed to write ${uri}`, collected.issues);
    }
    Logger.Info(TAG, `exported ${collected.snapshot.connections.length} connection(s) to ${uri}`);
    return succeededRunResult(collected.snapshot, 'exported', collected.issues);
}

/** 应用内"还原"：读用户选的备份文件，写回配置目录，再把配置推进内存。 */
export async function importBackupFromUri(uri: string): Promise<IBackupRunResult> {
    const text = await readFullFile(uri);
    if (text === undefined) {
        return failedRunResult(`failed to read ${uri}`,
            [makeBackupIssue(BackupIssueCode.NotJson, `cannot read ${uri}`, true)]);
    }

    const decoded = decodeBackupEnvelope(text);
    const envelope = decoded.envelope;
    if (envelope === undefined) {
        return failedRunResult(decoded.issues[0].detail, decoded.issues);
    }

    const baseDir = ConfigManager.configDirPath;
    if (!await writeConfigFilesToDir(baseDir, renderBackupConfigFiles(envelope.snapshot))) {
        return failedRunResult('failed to write the configuration files', decoded.issues);
    }

    // 让配置目录里的快照和刚导入的数据保持一致，系统备份接着用它。
    await writeConsolidatedBackup(baseDir);
    await ConfigManager.reloadConfigurations();

    Logger.Info(TAG, `imported ${envelope.snapshot.connections.length} connection(s) from ${uri}`);
    return succeededRunResult(envelope.snapshot, 'imported', decoded.issues);
}
