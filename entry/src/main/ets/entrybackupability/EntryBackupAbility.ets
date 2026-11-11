// SPDX-License-Identifier: GPL-3.0-or-later

/**
 * 系统级备份还原（换机克隆、云备份、应用迁移）。
 *
 * 备份恢复框架会把 backup_config 覆盖到的目录原样搬走，这里要做的是让
 * 搬走的东西是自洽的：备份前在配置目录里留下一份带版本号的 backup.json，
 * 还原后按数据来源的版本决定是修复、不动、还是推倒重来。
 * 判断和处理逻辑全在 core/backup/ 下，和 Settings 页的导出导入共用。
 */

import { BackupExtensionAbility, BundleVersion } from '@kit.CoreFileKit';
import Logger from '../utils/Logging';
import { ConfigManager } from '../core/config/ConfigManager';
import { BackupRestoreAction, fatalIssuesOf } from '../core/backup/BackupModel';
import { restoreSystemBackup, writeConsolidatedBackup } from '../core/backup/BackupStore';

const TAG = 'Hv2ray-BackupAbility';

export default class EntryBackupAbility extends BackupExtensionAbility {
    async onBackup() {
        Logger.Info(TAG, 'onBackup');
        const collected = await writeConsolidatedBackup(ConfigManager.configDirPath);
        const fatal = fatalIssuesOf(collected.issues);
        if (fatal.length > 0) {
            Logger.Error(TAG, `onBackup left no snapshot: ${fatal[0].detail}`);
            return;
        }
        Logger.Info(TAG, `onBackup ok, ${collected.snapshot.groups.length} group(s), ` +
            `${collected.snapshot.connections.length} connection(s)`);
    }

    async onRestore(bundleVersion: BundleVersion) {
        Logger.Info(TAG, `onRestore from version ${bundleVersion.name} (${bundleVersion.code})`);
        const outcome = await restoreSystemBackup(ConfigManager.configDirPath,
            { code: bundleVersion.code, name: bundleVersion.name });
        for (const issue of outcome.issues) {
            Logger.Warn(TAG, `${issue.code}: ${issue.detail}`);
        }
        if (outcome.plan.action === BackupRestoreAction.Keep) {
            Logger.Info(TAG, 'onRestore ok, the restored files were kept as they are');
            return;
        }
        Logger.Info(TAG, `onRestore ${outcome.plan.action} applied=${outcome.applied}, ${outcome.plan.reason}`);
    }
}
