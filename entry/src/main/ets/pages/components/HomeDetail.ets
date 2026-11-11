import { vpnExtension } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { BUNDLE_NAME } from 'BuildProfile';
import { KernelEventType } from '../../utils/Common';
import {
    GlobalKernelStatus,
    GlobalStat,
    kernelStatusColor,
    kernelStatusLabel,
    prettyPrintBytes
} from '../PageCommon';
import { VCoreManager } from '../../vpn/VCoreManager';
import { ConfigManager } from '../../core/config/ConfigManager';
import { ConfigRoot } from '../../core/config/Config';
import { ConfigurationBuilder } from '../../core/config/Generation';
import { stopKernel } from './HomeCommon';
import Logger from '../../utils/Logging';

const TAG = 'Hv2ray-HomePage';

@ComponentV2
struct SpeedStatsRow {
    @Require @Param message: ResourceStr;
    @Require @Param value: number;
    @Param suffix: string = '';

    build() {
        Row({ space: 8 }) {
            Text(this.message)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)

            Text(prettyPrintBytes(this.value) + this.suffix)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .textAlign(TextAlign.End)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .width('100%')
    }
}

@ObservedV2
class ConnectionInfo {
    public readonly config: ConfigRoot;
    @Trace connectionName: string;
    @Trace remoteHost: string = 'Unknown';
    @Trace remotePort: number = 0;
    @Trace protocol: string = 'unknown';
    @Trace transport: string = 'unknown';

    constructor(connId: string, root: ConfigRoot) {
        this.config = root;
        this.connectionName = ConfigManager.getConnection(connId)?.name ?? "<invalid>";
        if (root.outbounds && root.outbounds.length > 0) {
            this.remoteHost = root.outbounds[0].settings['address'] as string;
            this.remotePort = root.outbounds[0].settings['port'] as number;
            this.protocol = root.outbounds[0].protocol;
            this.transport = root.outbounds[0].streamSettings?.transport ?? '<unknown>';
        }
    }

    static async getConnectionInfo(connId: string): Promise<ConnectionInfo> {
        const root = (await ConfigManager.loadConnectionFromFile(connId))!;
        return new ConnectionInfo(connId, root);
    }
}

@ComponentV2
export struct HomeConnectionDetail {
    @Require @Param connectionIdValue: string;
    /**
     * Full VPN 开关不能由详情实例持有：切换连接时 NavDestination 会被重建，
     * 实例内状态会复位并静默改变下次启动时生成的路由模式。状态由宿主持有。
     */
    @Param isFullVpnValue: boolean = false;
    @Param isSplitMode: boolean = false;
    @Event onFullVpnChange: (isFullVpn: boolean) => void = (_isFullVpn: boolean): void => {
    };
    @Local connectionInfo: ConnectionInfo | undefined = undefined;

    @Monitor('connectionIdValue')
    async onConnectionIdChanged() {
        await this.reloadConnectionInfo();
    }

    async aboutToAppear(): Promise<void> {
        await this.reloadConnectionInfo();
    }

    private async reloadConnectionInfo(): Promise<void> {
        if (this.connectionIdValue.length === 0) {
            this.connectionInfo = undefined;
            return;
        }
        this.connectionInfo = await ConnectionInfo.getConnectionInfo(this.connectionIdValue);
    }

    private get kernelStatus(): KernelEventType {
        return GlobalKernelStatus.status;
    }

    private getCurrentConfig(): string {
        if (!this.connectionInfo) {
            return '';
        }

        const TUNFD_PLACEHOLDER = "<<FDXXX>>";
        const generator = new ConfigurationBuilder(this.connectionInfo.config);
        generator.addStatsApi();
        generator.addHttpInbound();
        generator.addTunInbound(TUNFD_PLACEHOLDER);
        generator.addFreedomOutbound(!this.isFullVpnValue);
        generator.addRules();
        generator.addWireguard(ConfigManager.wireGuard);
        const final = generator.build();
        return JSON.stringify(final);
    }

    private async doStartKernel(): Promise<void> {
        const context = this.getUIContext()
            .getHostContext()!;
        const fileDir = context.getApplicationContext().filesDir;
        Logger.Info(TAG, `fileDir: '${fileDir}'`);

        fs.unlink(fileDir + '/' + 'error.log')
            .catch((e: BusinessError) => {
                Logger.Error(TAG, `failed to remove error.log:${JSON.stringify(e)}`);
            });

        fs.unlink(fileDir + '/' + 'access.log')
            .catch((e: BusinessError) => {
                Logger.Error(TAG, `failed to remove access.log:${JSON.stringify(e)}`);
            });

        let accessFile = await fs.open(fileDir + '/' + 'access.log', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
            .catch((e: BusinessError) => {
                Logger.Error(TAG, `failed to create access.log:${JSON.stringify(e)}`);
            });

        let errorFile = await fs.open(fileDir + '/' + 'error.log', fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
            .catch((e: BusinessError) => {
                Logger.Error(TAG, `failed to create access.log:${JSON.stringify(e)}`);
            });

        if (accessFile) {
            fs.close(accessFile)
                .catch(() => {
                    Logger.Error(TAG, `failed to close access log`)
                });
        }
        if (errorFile) {
            fs.close(errorFile)
                .catch(() => {
                    Logger.Error(TAG, `failed to close error log`)
                });
        }

        let params: VCoreManager.StartVCoreParams = {
            config: this.getCurrentConfig(),
            statsPort: 18888,
            directTag: 'direct',
            proxyTag: 'outbound',
        }
        let want: Want = {
            bundleName: BUNDLE_NAME,
            abilityName: 'VpnAbility',
            parameters: {
                'params': JSON.stringify(params),
            }
        };

        try {
            await vpnExtension.startVpnExtensionAbility(want);
        } catch (e) {
            Logger.Error(TAG, `failed to start VpnAbility: ${JSON.stringify(e)}`);
        }
        Logger.Info(TAG, `onStart done`);
    }

    @Builder
    speedStats() {
        Column({ space: 10 }) {
            SpeedStatsRow({ message: $r('app.string.stat_proxy_up'), value: GlobalStat.proxyUpRate, suffix: '/s' })
            SpeedStatsRow({ message: $r('app.string.stat_proxy_down'), value: GlobalStat.proxyDownRate, suffix: '/s' })

            SpeedStatsRow({ message: $r('app.string.stat_direct_up'), value: GlobalStat.directUpRate, suffix: '/s' })
            SpeedStatsRow({ message: $r('app.string.stat_direct_down'), value: GlobalStat.directDownRate, suffix: '/s' })

            SpeedStatsRow({ message: $r('app.string.stat_total_up'), value: GlobalStat.proxyUpTotal })
            SpeedStatsRow({ message: $r('app.string.stat_total_down'), value: GlobalStat.proxyDownTotal })
        }
        .width('100%')
    }

    @Builder
    statusComponent() {
        Row({ space: 16 }) {
            Circle()
                .width(48)
                .height(48)
                .foregroundColor(kernelStatusColor(this.kernelStatus))
            Text(kernelStatusLabel(this.kernelStatus))
                .fontSize(28)
                .fontWeight(FontWeight.Bold)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
    }

    @Builder
    controlButtons() {
        // API 20 起 GridRow 不设 columns 时默认列数为 {xs:2,sm:4,md:8,lg:12}，
        // 这里显式固定 12 列，span 才按下面的比例生效。
        // 断点以本容器宽度为参照：详情区在双栏下可能只有 360vp，
        // 若沿用默认的窗口参照会把按钮压到不可读的尺寸。
        GridRow({
            gutter: { x: 12, y: 12 },
            columns: 12,
            breakpoints: { reference: BreakpointsReference.ComponentSize }
        }) {
            GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4 } }) {
                Button(this.isFullVpnValue ? $r('app.string.btn_full_vpn') : $r('app.string.btn_wg_only'))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .backgroundColor(this.isFullVpnValue ? $r('sys.color.brand') : $r('sys.color.comp_background_secondary'))
                    .fontColor(this.isFullVpnValue ? $r('sys.color.font_on_primary') : $r('sys.color.font_primary'))
                    .padding(16)
                    .width('100%')
                    .onClick(async () => {
                        this.onFullVpnChange(!this.isFullVpnValue);
                    })
            }

            GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4 } }) {
                Button(this.kernelStatus === KernelEventType.Started ? $r('app.string.btn_restart') : $r('app.string.btn_start'))
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .backgroundColor($r('sys.color.brand'))
                    .fontColor($r('sys.color.font_on_primary'))
                    .padding(16)
                    .width('100%')
                    .onClick(async () => {
                        Logger.Info(TAG, `onStart`);
                        const currentStatus = this.kernelStatus;
                        await vpnExtension.stopVpnExtensionAbility({
                            bundleName: BUNDLE_NAME,
                            abilityName: 'VpnAbility',
                        })
                            .catch(() => {
                                Logger.Error(TAG, `failed to stop VpnAbility prior to start`)
                            });

                        if (currentStatus === KernelEventType.Started) {
                            setTimeout(() => {
                                this.doStartKernel();
                            }, 500);
                        } else {
                            await this.doStartKernel();
                        }

                    })
            }

            if (this.kernelStatus === KernelEventType.Started) {
                GridCol({ span: { xs: 12, sm: 6, md: 4, lg: 4 } }) {
                    Button($r('app.string.btn_stop'))
                        .fontSize(18)
                        .fontWeight(FontWeight.Bold)
                        .backgroundColor($r('sys.color.alert'))
                        .fontColor($r('sys.color.font_on_primary'))
                        .padding(16)
                        .width('100%')
                        .onClick(async () => {
                            await stopKernel();
                        })
                }
            }
        }
        .width('100%')
    }

    @Builder
    selectedConnectionInfo() {
        Column({ space: 8 }) {
            if (this.connectionInfo) {
                Text(this.connectionInfo.remoteHost + ':' + this.connectionInfo.remotePort)
                    .fontWeight(FontWeight.Bold)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    // 主机名里的点也是断行点，按词断会只留下前半段；和左列表一样按字符截。
                    .wordBreak(WordBreak.BREAK_ALL)
                Text(this.connectionInfo.protocol + '/' + this.connectionInfo.transport)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .wordBreak(WordBreak.BREAK_ALL)
            } else {
                Text($r('app.string.none_selected'))
            }
        }
        .width('100%')
    }

    build() {
        NavDestination() {
            Scroll() {
                Column({ space: 24 }) {
                    this.selectedConnectionInfo();
                    this.statusComponent();
                    this.speedStats();
                    this.controlButtons();
                }
                .width('100%')
                .constraintSize({ maxWidth: 800 })
                .padding(16)
            }
            .width('100%')
            .height('100%')
            .align(Alignment.Top)
        }
        .title(this.connectionInfo ? this.connectionInfo.connectionName : $r('app.string.tab_home'))
        .onBackPressed((): boolean => {
            // 双栏下导航栏本来就在旁边，弹出详情只会让内容区留白，直接消费返回事件。
            return this.isSplitMode;
        })
    }
}
