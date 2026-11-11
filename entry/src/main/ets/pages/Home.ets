import { vpnExtension } from '@kit.NetworkKit';
import { KernelEvent, KernelEventType } from '../utils/Common';
import fs from '@ohos.file.fs';
import { CommonEventUtils } from '../utils/CommonEventUtils';
import { GlobalStat, prettyPrintBytes } from './PageCommon'
import { VCoreManager } from '../vpn/VCoreManager';
import { IConnection, IGroup } from '../core/config/ConfigCommon';
import { ConfigManager } from '../core/config/ConfigManager';
import { ConfigRoot } from '../core/config/Config';
import Logger from '../utils/Logging';
import { Want } from '@kit.AbilityKit';
import { BUNDLE_NAME } from 'BuildProfile';
import { ConfigurationBuilder } from '../core/config/Generation';
import { FilterList, FilterOption, LayoutType, ResultItem } from 'module_filter_list';


@ComponentV2
struct IndexAAA {
    types: string[] = [];
    styles: string[] = [];
    @Local typeIndex: number = 0;
    @Local styleIndex: number = 0;
    @Local listArr: string[] = [];
    @Local filterOptions: FilterOption[] = [];

    private resText(name: Resource): string {
        try {
            return this.getUIContext()
                .getHostContext()!
                .resourceManager
                .getStringSync(name.id);
        } catch (error) {
            Logger.Error(TAG, `failed to load resource ${name.id}: ${JSON.stringify(error)}`);
            return '';
        }
    }

    aboutToAppear(): void {
        this.types = [
            this.resText($r('app.string.demo_room_1bed')),
            this.resText($r('app.string.demo_room_2bed')),
            this.resText($r('app.string.demo_room_3bed')),
            this.resText($r('app.string.demo_room_4bed')),
        ];
        this.styles = [
            this.resText($r('app.string.demo_style_wood')),
            this.resText($r('app.string.demo_style_minimal')),
            this.resText($r('app.string.demo_style_new_chinese')),
            this.resText($r('app.string.demo_style_cream')),
            this.resText($r('app.string.demo_style_wood')),
            this.resText($r('app.string.demo_style_minimal')),
            this.resText($r('app.string.demo_style_new_chinese')),
        ];
        this.filterOptions = [
            new FilterOption(this.resText($r('app.string.demo_filter_room_type')), this.typeIndex, this.types),
            new FilterOption(this.resText($r('app.string.demo_filter_style')), this.styleIndex, this.styles),
        ];
    }

    private onFilterListChange(res: ResultItem[]) {
        while (this.listArr.length > 0) {
            this.listArr.pop();
        }
        Logger.Error(TAG, `!!!!! ${JSON.stringify(res)}`);
        for (const r of res) {
            this.listArr.push(`${r.filterName} - ${r.selectIndex}`);
        }
    }

    build() {
        Column() {
            FilterList(
                {
                    filterOptions: this.filterOptions,
                    layoutStyle: LayoutType.SPLIT,
                    onChange: (res: ResultItem[]) => {
                        this.onFilterListChange(res);
                    },
                },
            ) {
                List({ space: 12 }) {
                    ForEach(this.listArr, (item: string, _index: number) => {
                        ListItem() {
                            Column({ space: 12 }) {
                                Image($r('app.media.app_icon'))
                                    .width('100%')
                                    .height(140)
                                    .borderRadius(16)
                                    .draggable(false)

                                Text(item)
                            }
                        }
                    })
                }
                .width('100%')
                .height('100%')
                .padding({ top: 12, right: 16, left: 16 })
                .layoutWeight(1)
            }
        }
    }
}

const TAG = "Hv2ray-HomePage"

@ComponentV2
struct SpeedStatsRow {
    @Require @Param message: ResourceStr;
    @Require @Param value: number;
    @Param suffix: string = '';

    build() {
        Row() {
            Text(this.message)
                .fontSize(20)
                .width(200)
                .fontWeight(FontWeight.Bold)

            Text(prettyPrintBytes(this.value) + this.suffix)
                .fontSize(20)
                .fontWeight(FontWeight.Bold)
                .textAlign(TextAlign.End)
        }
        .justifyContent(FlexAlign.SpaceBetween)
        .width('70%')
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
export struct Home {
    @Local kernelStatus: KernelEventType = KernelEventType.Stopped;
    @Local selectedConnection: string = '';
    @Local connectionInfo: ConnectionInfo | undefined = undefined;

    @Monitor('selectedConnection')
    async onSelectedConnectionChanged() {
        this.connectionInfo = await ConnectionInfo.getConnectionInfo(this.selectedConnection);
    }

    private get kernelStatusColor(): Color {
        switch (this.kernelStatus) {
            case KernelEventType.Starting: return Color.Yellow;
            case KernelEventType.Started: return Color.Green;
            case KernelEventType.Crashed: return Color.Red;
            case KernelEventType.Stopped: return Color.Blue;
        }
    }

    private get kernelStatusLabel(): Resource {
        switch (this.kernelStatus) {
            case KernelEventType.Starting: return $r('app.string.status_starting');
            case KernelEventType.Started: return $r('app.string.status_started');
            case KernelEventType.Crashed: return $r('app.string.status_crashed');
            case KernelEventType.Stopped: return $r('app.string.status_stopped');
        }
    }

    async aboutToAppear() {
        CommonEventUtils.subscribeKernelEvent(async (kernelEvent: KernelEvent) => {
            this.kernelStatus = kernelEvent.type;
            if (kernelEvent.type === KernelEventType.Crashed) {
                await this.doStopKernel();
                await this.getUIContext()
                    .getPromptAction()
                    .showDialog({
                        message: kernelEvent.message.join('\n') ?? 'failed'
                    })     
                    .catch(() => {
                        Logger.Error(TAG, `show dialog failed!`);
                    })
            }
        });
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
        generator.addFreedomOutbound(!this.isFullVpn);
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
    }

    @Builder
    kernelStatusIcon() {
        Circle()
            .width(100)
            .height(100)
            .foregroundColor(this.kernelStatusColor)
    }

    @Builder
    statusComponent() {
        Row({ space: 32 }) {
            this.kernelStatusIcon()
            Text(this.kernelStatusLabel)
                .fontSize(40)
                .fontWeight(FontWeight.Bold)
        }
    }

    @Local private isFullVpn: boolean = false;

    @Builder
    controlButtons() {
        Row({ space: 30 }) {
            Button(this.isFullVpn ? $r('app.string.btn_full_vpn') : $r('app.string.btn_wg_only'))
                .fontSize(18)
                .fontWeight(FontWeight.Bold)
                .backgroundColor(this.isFullVpn ? Color.Green : Color.Blue)
                .padding(20)
                .width(150)
                .onClick(async () => {
                    this.isFullVpn = !this.isFullVpn;
                })

            Button(this.kernelStatus === KernelEventType.Started ? $r('app.string.btn_restart') : $r('app.string.btn_start'))
                .fontSize(30)
                .fontWeight(FontWeight.Bold)
                .backgroundColor(Color.Green)
                .padding(20)
                .width(150)
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

            if (this.kernelStatus === KernelEventType.Started) {
                Button($r('app.string.btn_stop'))
                    .fontSize(30)
                    .fontWeight(FontWeight.Bold)
                    .backgroundColor(Color.Red)
                    .padding(20)
                    .width(150)
                    .onClick(async () => {
                        await this.doStopKernel();
                    })
            }
        }
    }

    private async doStopKernel() {
        VCoreManager.StopVCore();
        try {
            await vpnExtension.stopVpnExtensionAbility({
                bundleName: BUNDLE_NAME,
                abilityName: 'VpnAbility',
            });
        } catch (error) {
            Logger.Error(TAG, `failed to stop VpnAbility: ${JSON.stringify(error)}`);
        }
    }

    @Builder
    selectedConnectionInfo() {
        Column({ space: 8 }) {
            if (this.connectionInfo) {
                Text(this.connectionInfo.connectionName)
                    .fontSize(30)
                    .fontWeight(FontWeight.Bold)
                    .margin({ bottom: 12 })
                Text(this.connectionInfo.remoteHost + ':' + this.connectionInfo.remotePort)
                    .fontWeight(FontWeight.Bold)
                Text(this.connectionInfo.protocol + '/' + this.connectionInfo.transport)
            } else {
                Text($r('app.string.none_selected'))
            }
        }
        .width('100%')
        .margin({ bottom: 50 })
    }

    @Builder
    connectionItem(conn: IConnection | undefined) {
        Row() {
            if (conn) {
                Button(conn.name)
                    .width('100%')
                    .onClick(() => {
                        this.selectedConnection = conn.id;
                    })
                    .backgroundColor(this.selectedConnection === conn.id ? Color.Red : undefined)
            } else {
                Text($r('app.string.invalid_option'))
            }
        }
        .width('100%')
    }

    @Builder
    groupItem(group: IGroup) {
        Column() {
            Row() {
                Text(group.name)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .margin({ left: 8 })
                Button($r('app.string.btn_edit'))
            }
            .borderRadius(8)
            .padding(8)
            .justifyContent(FlexAlign.SpaceBetween)
            .backgroundColor($r('sys.color.gray_03'))
            .height(48)
            .width('100%')

            List({ space: 16 }) {
                ForEach(group.connections, (connId: string) => {
                    ListItem() {
                        this.connectionItem(ConfigManager.getConnection(connId));
                    }
                }, (connId: string) => connId)
            }
            .padding({ left: 8, right: 8 })
            .width('100%')
            .height(300)
        }
    }

    @Builder
    addSomethingButton() {
        Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus'))
                .fontColor([$r('sys.color.font_primary')])
                .fontSize(24)
        }
        .backgroundColor($r('sys.color.brand'))
        .width(48)
        .height(48)
    }

    build() {
        Row() {
            Column() {
                // list all groups
                List({ space: 8 }) {
                    ForEach(Array.from(ConfigManager.allGroups.values()), (group: IGroup) => {
                        ListItem() {
                            this.groupItem(group);
                        }
                    }, (group: IGroup) => group.id)

                    ListItem() {
                        IndexAAA()
                            .width('100%')
                    }
                    .width('100%')
                }
                .backgroundColor($r('sys.color.gray_02'))
                .padding(8)
                .width('100%')
                .height('100%')

                Row() {
                    this.addSomethingButton();
                }
                .hitTestBehavior(HitTestMode.Transparent)
                .justifyContent(FlexAlign.Center)
                .width('100%')
                .position({ bottom: '20vp' })
            } 
            .width(300)
            // .constraintSize({ minWidth: 300 })
            .height('100%')

            Column({ space: 40 }) {
                this.selectedConnectionInfo();
                this.statusComponent();
                this.speedStats();
                this.controlButtons();
            }
            .padding(16)
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .height('100%')
        }
        .height('100%')
        .width('100%')
    }
}