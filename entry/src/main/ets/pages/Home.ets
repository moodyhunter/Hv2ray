import { vpnExtension } from '@kit.NetworkKit';
import { KernelEvent, KernelEventType } from '../utils/Common';
import fs from '@ohos.file.fs';
import { CommonEventUtils } from '../utils/CommonEventUtils';
import {
    GlobalKernelStatus,
    GlobalStat,
    kernelStatusColor,
    kernelStatusLabel,
    prettyPrintBytes
} from './PageCommon';
import { VCoreManager } from '../vpn/VCoreManager';
import { IConnection, IGroup } from '../core/config/ConfigCommon';
import { ConfigManager } from '../core/config/ConfigManager';
import { ConfigRoot } from '../core/config/Config';
import Logger from '../utils/Logging';
import { Want } from '@kit.AbilityKit';
import { BUNDLE_NAME } from 'BuildProfile';
import { ConfigurationBuilder } from '../core/config/Generation';
import { FilterList, FilterOption, LayoutType, ResultItem } from 'module_filter_list';

const TAG = "Hv2ray-HomePage"

/**
 * Navigation 自适应分栏参数：宽度大于 NAV_BAR_WIDTH + MIN_CONTENT_WIDTH 时
 * NavigationMode.Auto 才进入双栏模式，否则自动降级为单栏。
 */
const DETAIL_ROUTE = 'homeConnectionDetail';
const NAV_BAR_WIDTH = 300;
const MIN_CONTENT_WIDTH = 360;

/** 分组列表的列宽约束：窄屏单列，宽屏/横屏自动多列 */
const GROUP_LANE_MIN_WIDTH = 280;
const GROUP_LANE_MAX_WIDTH = 520;
const GROUP_LANE_GUTTER = 8;

interface HomeDetailParam {
    connectionIdValue: string;
}

async function stopKernel(): Promise<void> {
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
struct HomeConnectionDetail {
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
                    .backgroundColor(this.isFullVpnValue ? Color.Green : Color.Blue)
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
                    .backgroundColor(Color.Green)
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
                        .backgroundColor(Color.Red)
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
                Text(this.connectionInfo.protocol + '/' + this.connectionInfo.transport)
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
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

@ComponentV2
export struct Home {
    @Local private pathStack: NavPathStack = new NavPathStack();
    @Local private selectedConnection: string = '';
    @Local private isFullVpn: boolean = false;
    @Local private navMode: NavigationMode = NavigationMode.Stack;

    async aboutToAppear() {
        CommonEventUtils.subscribeKernelEvent(async (kernelEvent: KernelEvent) => {
            if (kernelEvent.type === KernelEventType.Crashed) {
                await stopKernel();
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

    private showDetail(connectionId: string): void {
        this.selectedConnection = connectionId;
        const param: HomeDetailParam = { connectionIdValue: connectionId };
        if (this.pathStack.size() > 0) {
            this.pathStack.replacePath({ name: DETAIL_ROUTE, param: param });
        } else {
            this.pathStack.pushDestination({ name: DETAIL_ROUTE, param: param })
                .catch(() => {
                    Logger.Error(TAG, `failed to open ${DETAIL_ROUTE}`);
                });
        }
    }

    /**
     * 双栏模式下内容区默认为空，这里补上详情页，保证宽屏（平板 / 2in1）上
     * 状态、流量、启停按钮与适配前一样始终可见。
     */
    private onNavigationModeChanged(mode: NavigationMode): void {
        this.navMode = mode;
        if (mode === NavigationMode.Split && this.pathStack.size() === 0) {
            this.showDetail(this.selectedConnection);
        }
    }

    @Builder
    detailPageMap(name: string, param: Object) {
        if (name === DETAIL_ROUTE) {
            HomeConnectionDetail({
                connectionIdValue: (param as HomeDetailParam).connectionIdValue,
                isFullVpnValue: this.isFullVpn,
                isSplitMode: this.navMode === NavigationMode.Split,
                onFullVpnChange: (isFullVpn: boolean): void => {
                    this.isFullVpn = isFullVpn;
                },
            })
        }
    }

    @Builder
    kernelStatusSummary() {
        Row({ space: 8 }) {
            Circle()
                .width(12)
                .height(12)
                .foregroundColor(kernelStatusColor(GlobalKernelStatus.status))
            Text(kernelStatusLabel(GlobalKernelStatus.status))
                .fontSize(14)
        }
        .padding({ left: 8, top: 4, bottom: 4 })
        .width('100%')
    }

    @Builder
    connectionItem(conn: IConnection | undefined) {
        Row() {
            if (conn) {
                Button(conn.name)
                    .width('100%')
                    .onClick(() => {
                        this.showDetail(conn.id);
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

            // 原先这里是内嵌的 List.height(300)：固定高度 + 外层列表里再套滚动容器，
            // 窄屏下既不能完整显示也没法自适应。改为随内容增高的 Column，
            // 多列能力交给外层分组列表的 lanes（按容器宽度自动分列）。
            Column({ space: 8 }) {
                ForEach(group.connections, (connId: string) => {
                    this.connectionItem(ConfigManager.getConnection(connId));
                }, (connId: string) => connId)
            }
            .padding({ left: 8, right: 8, top: 8, bottom: 8 })
            .width('100%')
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
        Navigation(this.pathStack) {
            Column() {
                this.kernelStatusSummary();

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
                .lanes({ minLength: GROUP_LANE_MIN_WIDTH, maxLength: GROUP_LANE_MAX_WIDTH }, GROUP_LANE_GUTTER)
                .layoutWeight(1)

                Row() {
                    this.addSomethingButton();
                }
                .hitTestBehavior(HitTestMode.Transparent)
                .justifyContent(FlexAlign.Center)
                .width('100%')
                .position({ bottom: '20vp' })
            }
            .backgroundColor($r('sys.color.gray_02'))
            .padding(8)
            .width('100%')
            .height('100%')
        }
        .navDestination(this.detailPageMap)
        .mode(NavigationMode.Auto)
        .navBarWidth(NAV_BAR_WIDTH)
        .minContentWidth(MIN_CONTENT_WIDTH)
        .hideTitleBar(true)
        .onNavigationModeChange((mode: NavigationMode): void => {
            this.onNavigationModeChanged(mode);
        })
        .width('100%')
        .height('100%')
    }
}
