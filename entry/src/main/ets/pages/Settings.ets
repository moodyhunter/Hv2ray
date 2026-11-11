import Logger from '../utils/Logging';
import { Utils } from '../utils/Common';
import { ConfigManager } from '../core/config/ConfigManager';
import { parseCidr, WireGuardSettings } from '../core/config/WgSettings';
import { TUN_INTERFACE_MTU } from '../core/config/Generation';
import { FilterListDemo } from './FilterListDemo';
import { DEBUG } from 'BuildProfile';
import { picker } from '@kit.CoreFileKit';
import common from '@ohos.app.ability.common';
import {
    BACKUP_FILE_SUFFIX,
    BackupIssueCode,
    suggestBackupFileName
} from '../core/backup/BackupModel';
import { exportBackupToUri, IBackupRunResult, importBackupFromUri } from '../core/backup/BackupStore';

const TAG = "Hv2ray-Settings"

interface WgFormFailure {
    reason: string;
    message: ResourceStr;
}

@ComponentV2
export struct Settings {
    @Local private wgPrivateKey: string = '';
    @Local private wgPeerPublicKey: string = '';
    @Local private wgPeerEndpoint: string = '';
    @Local private wgLocalIp: string = '';
    @Local private wgMtu: string = '';
    @Local private wgKeepalive: string = '';
    @Local private wgRoutes: string = '';
    /** 备份/还原要走文件选择器，期间禁用按钮，避免并发跑两次。 */
    @Local private isBackupBusy: boolean = false;

    aboutToAppear(): void {
        Logger.Info(TAG, `aboutToAppear`);
        this.loadFromManager();
    }

    private loadFromManager(): void {
        const wg: WireGuardSettings = ConfigManager.wireGuard;
        this.wgPrivateKey = wg.privateKey;
        this.wgPeerPublicKey = wg.peerPublicKey;
        this.wgPeerEndpoint = wg.peerEndpoint;
        this.wgLocalIp = wg.localIp;
        this.wgMtu = `${wg.mtu}`;
        this.wgKeepalive = `${wg.keepaliveInterval}`;
        this.wgRoutes = wg.routes.join('\n');
    }

    private parseRoutes(input: string): string[] {
        const result: string[] = [];
        for (const line of input.split('\n')) {
            for (const part of line.split(',')) {
                const route = part.trim();
                if (route.length > 0) {
                    result.push(route);
                }
            }
        }
        return result;
    }

    private parsePositiveInt(input: string): number {
        const text = input.trim();
        if (!Utils.isUnsignedDecimal(text)) {
            return -1;
        }
        const value = parseInt(text);
        if (value <= 0) {
            return -1;
        }
        return value;
    }

    private formatText(name: Resource, arg: string | number): string {
        try {
            return this.getUIContext()
                .getHostContext()!
                .resourceManager
                .getStringSync(name.id, arg);
        } catch (error) {
            Logger.Error(TAG, `failed to format resource ${name.id}: ${JSON.stringify(error)}`);
            return 'validation failed';
        }
    }

    /**
     * Returns the reason why the form cannot be saved, or undefined when
     * every field looks usable.
     */
    private getValidationFailure(): WgFormFailure | undefined {
        if (this.wgPrivateKey.trim().length === 0) {
            return { reason: 'private_key_empty', message: $r('app.string.err_wg_private_key') };
        }
        if (this.wgPeerPublicKey.trim().length === 0) {
            return { reason: 'peer_public_key_empty', message: $r('app.string.err_wg_peer_public_key') };
        }
        if (this.wgPeerEndpoint.trim().length === 0) {
            return { reason: 'peer_endpoint_empty', message: $r('app.string.err_wg_peer_endpoint') };
        }
        if (this.wgLocalIp.trim().length === 0) {
            return { reason: 'local_ip_empty', message: $r('app.string.err_wg_local_ip') };
        }
        const mtu = this.parsePositiveInt(this.wgMtu);
        if (mtu < 0) {
            return { reason: 'mtu_not_positive', message: $r('app.string.err_wg_mtu_positive') };
        }
        if (mtu > TUN_INTERFACE_MTU) {
            return {
                reason: 'mtu_too_large',
                message: this.formatText($r('app.string.err_wg_mtu_max'), TUN_INTERFACE_MTU)
            };
        }
        if (this.parsePositiveInt(this.wgKeepalive) < 0) {
            return { reason: 'keepalive_not_positive', message: $r('app.string.err_wg_keepalive') };
        }
        const routes = this.parseRoutes(this.wgRoutes);
        if (routes.length === 0) {
            return { reason: 'no_routes', message: $r('app.string.err_wg_routes_required') };
        }
        for (const route of routes) {
            if (parseCidr(route) === undefined) {
                return {
                    reason: 'invalid_cidr',
                    message: this.formatText($r('app.string.err_wg_cidr_invalid'), route)
                };
            }
        }
        return undefined;
    }

    private async showFormError(message: ResourceStr): Promise<void> {
        await this.getUIContext()
            .getPromptAction()
            .showDialog({ message: message })
            .catch(() => {
                Logger.Error(TAG, `show dialog failed!`);
            });
    }

    private notifySaved(): void {
        try {
            this.getUIContext()
                .getPromptAction()
                .showToast({ message: $r('app.string.msg_wg_saved') });
        } catch (error) {
            Logger.Error(TAG, `failed to show saved toast: ${JSON.stringify(error)}`);
        }
    }

    private async doSave(): Promise<void> {
        const failure = this.getValidationFailure();
        if (failure !== undefined) {
            Logger.Error(TAG, `refusing to save: ${failure.reason}`);
            await this.showFormError(failure.message);
            return;
        }

        const wg = new WireGuardSettings();
        wg.privateKey = this.wgPrivateKey.trim();
        wg.peerPublicKey = this.wgPeerPublicKey.trim();
        wg.peerEndpoint = this.wgPeerEndpoint.trim();
        wg.localIp = this.wgLocalIp.trim();
        wg.mtu = this.parsePositiveInt(this.wgMtu);
        wg.keepaliveInterval = this.parsePositiveInt(this.wgKeepalive);
        wg.routes = this.parseRoutes(this.wgRoutes);

        const saved = await ConfigManager.saveWireGuardSettings(wg);
        if (!saved) {
            await this.showFormError($r('app.string.msg_wg_save_failed'));
            return;
        }
        Logger.Info(TAG, `wireguard settings saved, ${wg.routes.length} route(s)`);
        this.loadFromManager();
        this.notifySaved();
    }

    /** 失败时按问题码取本地文案，detail 只进日志。 */
    private backupFailureText(result: IBackupRunResult): ResourceStr {
        for (const issue of result.issues) {
            if (!issue.fatal) {
                continue;
            }
            switch (issue.code) {
                case BackupIssueCode.NotJson:
                    return $r('app.string.err_backup_not_json');
                case BackupIssueCode.NotABackup:
                    return $r('app.string.err_backup_not_ours');
                case BackupIssueCode.FormatTooNew:
                    return $r('app.string.err_backup_too_new');
                case BackupIssueCode.FormatTooOld:
                    return $r('app.string.err_backup_too_old');
                case BackupIssueCode.NoGroupsFile:
                    return $r('app.string.err_backup_no_groups');
                default:
                    return $r('app.string.msg_backup_failed');
            }
        }
        return $r('app.string.msg_backup_failed');
    }

    private logBackupIssues(result: IBackupRunResult): void {
        for (const issue of result.issues) {
            Logger.Warn(TAG, `backup ${issue.code}: ${issue.detail}`);
        }
    }

    private showToast(message: ResourceStr): void {
        try {
            this.getUIContext()
                .getPromptAction()
                .showToast({ message: message });
        } catch (error) {
            Logger.Error(TAG, `failed to show toast: ${JSON.stringify(error)}`);
        }
    }

    /** 文件选择器需要宿主上下文，拿不到时按失败处理。 */
    private pickerContext(): common.Context | undefined {
        return this.getUIContext()
            .getHostContext();
    }

    private async doBackup(): Promise<void> {
        const context = this.pickerContext();
        if (context === undefined) {
            Logger.Error(TAG, 'no host context, cannot open the document picker');
            await this.showFormError($r('app.string.msg_backup_failed'));
            return;
        }

        try {
            const saveOptions = new picker.DocumentSaveOptions();
            saveOptions.newFileNames = [suggestBackupFileName(Date.now())];
            saveOptions.fileSuffixChoices = [BACKUP_FILE_SUFFIX];
            const uris = await new picker.DocumentViewPicker(context)
                .save(saveOptions);
            if (uris.length === 0) {
                return;
            }

            const result = await exportBackupToUri(uris[0]);
            this.logBackupIssues(result);
            if (!result.ok) {
                Logger.Error(TAG, `backup failed: ${result.reason}`);
                await this.showFormError(this.backupFailureText(result));
                return;
            }
            Logger.Info(TAG, `backup done, ${result.groupCount} group(s), ${result.connectionCount} connection(s)`);
            this.showToast($r('app.string.msg_backup_done'));
        } catch (error) {
            Logger.Error(TAG, `backup failed: ${JSON.stringify(error)}`);
            await this.showFormError($r('app.string.msg_backup_failed'));
        }
    }

    private async doRestore(): Promise<void> {
        const context = this.pickerContext();
        if (context === undefined) {
            Logger.Error(TAG, 'no host context, cannot open the document picker');
            await this.showFormError($r('app.string.msg_backup_failed'));
            return;
        }

        try {
            const selectOptions = new picker.DocumentSelectOptions();
            selectOptions.maxSelectNumber = 1;
            selectOptions.fileSuffixFilters = [BACKUP_FILE_SUFFIX];
            const uris = await new picker.DocumentViewPicker(context)
                .select(selectOptions);
            if (uris.length === 0) {
                return;
            }
            this.confirmRestore(uris[0]);
        } catch (error) {
            Logger.Error(TAG, `restore failed: ${JSON.stringify(error)}`);
            await this.showFormError($r('app.string.msg_backup_failed'));
        }
    }

    /** 还原会覆盖本机配置，确认之后再动手。 */
    private confirmRestore(uri: string): void {
        this.getUIContext()
            .showAlertDialog({
                title: $r('app.string.restore_confirm_title'),
                message: $r('app.string.restore_confirm_message'),
                primaryButton: {
                    value: $r('app.string.btn_cancel'),
                    action: (): void => {
                    }
                },
                secondaryButton: {
                    value: $r('app.string.btn_replace'),
                    action: (): void => {
                        this.runRestore(uri);
                    }
                }
            });
    }

    private async runRestore(uri: string): Promise<void> {
        if (this.isBackupBusy) {
            return;
        }
        this.isBackupBusy = true;

        try {
            const result = await importBackupFromUri(uri);
            this.logBackupIssues(result);
            if (!result.ok) {
                Logger.Error(TAG, `restore failed: ${result.reason}`);
                await this.showFormError(this.backupFailureText(result));
                return;
            }
            Logger.Info(TAG, `restore done, ${result.groupCount} group(s), ${result.connectionCount} connection(s)`);
            this.loadFromManager();
            this.showToast(result.issues.length > 0
                ? $r('app.string.msg_restore_partial')
                : $r('app.string.msg_restore_done'));
        } catch (error) {
            Logger.Error(TAG, `restore failed: ${JSON.stringify(error)}`);
            await this.showFormError($r('app.string.msg_backup_failed'));
        } finally {
            this.isBackupBusy = false;
        }
    }

    build() {
        Scroll() {
            Column({ space: 16 }) {
                Text('WireGuard')
                    .fontSize(24)
                    .fontWeight(FontWeight.Bold)

                Text($r('app.string.wg_note'))
                    .fontSize(13)
                    .fontColor($r('sys.color.font_tertiary'))

                // 以本容器宽度为参照划分断点：窄屏标签在输入框上方，宽屏一行两列。
                // columns 必须显式写 12，否则 API 20 起默认按 {xs:2,sm:4,md:8,lg:12} 夹取 span。
                GridRow({
                    gutter: { x: 8, y: 8 },
                    columns: 12,
                    breakpoints: { reference: BreakpointsReference.ComponentSize }
                }) {
                    GridCol({ span: { xs: 12, sm: 12, md: 4, lg: 4 } }) {
                        Text($r('app.string.wg_private_key'))
                    }
                    GridCol({ span: { xs: 12, sm: 12, md: 8, lg: 8 } }) {
                        TextInput({ placeholder: $r('app.string.wg_private_key_hint'), text: this.wgPrivateKey!! })
                            .width('100%')
                    }

                    GridCol({ span: { xs: 12, sm: 12, md: 4, lg: 4 } }) {
                        Text($r('app.string.wg_peer_public_key'))
                    }
                    GridCol({ span: { xs: 12, sm: 12, md: 8, lg: 8 } }) {
                        TextInput({ placeholder: $r('app.string.wg_peer_public_key_hint'), text: this.wgPeerPublicKey!! })
                            .width('100%')
                    }

                    GridCol({ span: { xs: 12, sm: 12, md: 4, lg: 4 } }) {
                        Text($r('app.string.wg_peer_endpoint'))
                    }
                    GridCol({ span: { xs: 12, sm: 12, md: 8, lg: 8 } }) {
                        TextInput({ placeholder: 'host:port', text: this.wgPeerEndpoint!! })
                            .width('100%')
                    }

                    GridCol({ span: { xs: 12, sm: 12, md: 4, lg: 4 } }) {
                        Text($r('app.string.wg_local_ip'))
                    }
                    GridCol({ span: { xs: 12, sm: 12, md: 8, lg: 8 } }) {
                        TextInput({ placeholder: $r('app.string.wg_local_ip_hint'), text: this.wgLocalIp!! })
                            .width('100%')
                    }

                    GridCol({ span: { xs: 12, sm: 12, md: 4, lg: 4 } }) {
                        Text('MTU')
                    }
                    GridCol({ span: { xs: 12, sm: 12, md: 8, lg: 8 } }) {
                        TextInput({ placeholder: '1420', text: this.wgMtu!! })
                            .type(InputType.Number)
                            .width('100%')
                    }

                    GridCol({ span: { xs: 12, sm: 12, md: 4, lg: 4 } }) {
                        Text($r('app.string.wg_keepalive'))
                    }
                    GridCol({ span: { xs: 12, sm: 12, md: 8, lg: 8 } }) {
                        TextInput({ placeholder: '25', text: this.wgKeepalive!! })
                            .type(InputType.Number)
                            .width('100%')
                    }

                    GridCol({ span: { xs: 12, sm: 12, md: 12, lg: 12 } }) {
                        Column({ space: 4 }) {
                            Text($r('app.string.wg_routes'))
                            TextArea({ placeholder: $r('app.string.wg_routes_hint'), text: this.wgRoutes!! })
                                .constraintSize({ minHeight: 100 })
                                .width('100%')
                        }
                        .width('100%')
                    }

                    GridCol({ span: { xs: 6, sm: 6, md: 4, lg: 4 } }) {
                        Button($r('app.string.btn_save'))
                            .width('100%')
                            .onClick(async () => {
                                await this.doSave();
                            })
                    }
                    GridCol({ span: { xs: 6, sm: 6, md: 4, lg: 4 } }) {
                        Button($r('app.string.btn_reload'))
                            .width('100%')
                            .onClick(() => {
                                this.loadFromManager();
                            })
                    }
                }
                .alignItems(ItemAlign.Center)
                .width('100%')

                Divider()
                Text($r('app.string.backup_section_title'))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)

                Text($r('app.string.backup_note'))
                    .fontSize(13)
                    .fontColor($r('sys.color.font_tertiary'))

                // 文件选择器和写文件都是异步的，busy 期间禁用按钮，避免同时跑两份。
                GridRow({
                    gutter: { x: 8, y: 8 },
                    columns: 12,
                    breakpoints: { reference: BreakpointsReference.ComponentSize }
                }) {
                    GridCol({ span: { xs: 6, sm: 6, md: 4, lg: 4 } }) {
                        Button($r('app.string.btn_backup'))
                            .width('100%')
                            .enabled(!this.isBackupBusy)
                            .onClick(async () => {
                                this.isBackupBusy = true;
                                await this.doBackup();
                                this.isBackupBusy = false;
                            })
                    }
                    GridCol({ span: { xs: 6, sm: 6, md: 4, lg: 4 } }) {
                        Button($r('app.string.btn_restore'))
                            .width('100%')
                            .enabled(!this.isBackupBusy)
                            .onClick(async () => {
                                this.isBackupBusy = true;
                                await this.doRestore();
                                this.isBackupBusy = false;
                            })
                    }
                }
                .width('100%')

                // The vendored module_filter_list showcase is demo content, kept out of
                // the configuration list and only reachable from debug builds.
                if (DEBUG) {
                    Divider()
                    Text($r('app.string.demo_section_title'))
                        .fontSize(18)
                        .fontWeight(FontWeight.Bold)

                    FilterListDemo()
                        .width('100%')
                        .height(320)
                }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .constraintSize({ maxWidth: 900 })
            .padding(16)
        }
        .width('100%')
        .height('100%')
    }
}
