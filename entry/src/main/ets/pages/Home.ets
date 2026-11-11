import { vpnExtension } from '@kit.NetworkKit';
import { SymbolGlyphModifier, TextModifier } from '@kit.ArkUI';
import { KernelEvent, KernelEventType, Utils } from '../utils/Common';
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
import { ConfigManager, ConfigChangeListener } from '../core/config/ConfigManager';
import { ConfigRoot, StreamObject } from '../core/config/Config';
import { JsonObject } from '../core/config/ConfigDefs';
import { Connection } from '../core/config/Connection';
import Logger from '../utils/Logging';
import { Want } from '@kit.AbilityKit';
import { BUNDLE_NAME } from 'BuildProfile';
import { ConfigurationBuilder } from '../core/config/Generation';
import { HdsListItem, SuffixCustomBuilder } from '@kit.UIDesignKit';

const TAG = "Hv2ray-HomePage"

/**
 * Navigation 自适应分栏参数：宽度大于 NAV_BAR_WIDTH + MIN_CONTENT_WIDTH 时
 * NavigationMode.Auto 才进入双栏模式，否则自动降级为单栏。
 * NAV_BAR_MIN/MAX 是双栏下拖动分割线的允许区间；实际可用上限还会被 MIN_CONTENT_WIDTH 夹取。
 */
const DETAIL_ROUTE = 'homeConnectionDetail';
const NAV_BAR_WIDTH = 300;
const NAV_BAR_MIN_WIDTH = 240;
const NAV_BAR_MAX_WIDTH = 520;
const MIN_CONTENT_WIDTH = 360;

const MOVE_RADIO_GROUP = 'homeMoveConnectionGroup';
const MAX_PORT = 65535;

/**
 * 行高与组头高度显式固定；HdsListItemCard 的 cardHeight 用同一个值。
 * cardWidth 不要给百分比，见 HomeConnectionListItem 里的说明。
 */
const ROW_HEIGHT = 48;
const GROUP_HEADER_HEIGHT = 40;

/** 卡片间距：组内 4vp，组之间 6vp。分组不再用 CARD 样式，所以这两个值就是全部的间隔 */
const GROUP_ITEM_SPACING = 4;
const GROUP_SECTION_SPACING = 6;

/**
 * 菜单模态化：点非菜单区域时不再穿透触发下层 ListItem 的点击。
 * mask 在 2in1 上不生效（系统配置不显示菜单蒙层），所以真正起作用的是 modalMode；
 * 两者都给，手机/平板上有蒙层，2in1 上靠 modalMode 拦住穿透。
 */
const HOME_MENU_OPTIONS: MenuOptions = {
    modalMode: ModalMode.TARGET_WINDOW,
    mask: true,
};

interface HomeDetailParam {
    connectionIdValue: string;
}

/** 列表渲染用的派生视图，不持久化，只由 ConfigManager 的数据推导 */
interface HomeConnectionRow {
    connection: Connection;
    groupId: string;
}

interface HomeGroupRow {
    id: string;
    name: string;
    connections: HomeConnectionRow[];
}

interface HomeGroupOption {
    id: string;
    name: string;
}

@ObservedV2
class HomeEditDraft {
    @Trace connId: string = '';
    @Trace connName: string = '';
    @Trace hostText: string = '';
    @Trace portText: string = '';
    @Trace protocolText: string = '';
    @Trace transportText: string = '';
    @Trace groupId: string = '';
    @Trace groupOptions: HomeGroupOption[] = [];
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
struct HomeEditField {
    @Require @Param fieldLabel: Resource;
    @Require @Param fieldValue: string;
    @Param numericInput: boolean = false;
    @Event onFieldValue: (value: string) => void = (value: string): void => {
    };

    build() {
        Column({ space: 4 }) {
            Text(this.fieldLabel)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
            TextInput({ text: this.fieldValue })
                .type(this.numericInput ? InputType.Number : InputType.Normal)
                .width('100%')
                .onChange((value: string): void => {
                    this.onFieldValue(value);
                })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
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

/**
 * HDS 的文本槽只接受 `TextOptions { text, modifier }`，排版由 HDS 决定，但默认会让长名称换行。
 * 这里只补必要的截断：单行、省略号、按字符断（和自建行时一致）。字号/颜色留给 HDS 规格。
 */
class HomeRowTextModifier extends TextModifier {
    applyNormalAttribute(instance: TextAttribute): void {
        instance
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .wordBreak(WordBreak.BREAK_ALL);
    }
}

/**
 * 一行连接。用 UI Design Kit 的 `HdsListItem`（内部就是带 HDS 规格的 ListItem）：
 * 文本走 `textItem`，横滑删除走 `swipeActionOptions`，选中态走 `isSelected`，
 * 右键菜单走 `menuStyle` + `menuBuilder`。
 *
 * 菜单 builder 必须是**零参 @Builder 按引用**传（`menuBuilder: this.rowMenu`）；
 * 在属性位置调用带参 builder 会让菜单内容为空。
 */
@ComponentV2
struct HomeConnectionListItem {
    @Require @Param row: HomeConnectionRow;
    @Require @Param isSelected: boolean;
    @Event onRowOpen: (connectionId: string) => void = (_connectionId: string): void => {
    };
    @Event onEditRequested: (row: HomeConnectionRow) => void = (_row: HomeConnectionRow): void => {
    };
    @Event onDeleteRequested: (row: HomeConnectionRow) => void = (_row: HomeConnectionRow): void => {
    };
    private rowTextModifier: HomeRowTextModifier = new HomeRowTextModifier();

    @Builder
    rowMenu() {
        Menu() {
            MenuItem({
                content: $r('app.string.menu_edit_connection'),
                symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.square_and_pencil'))
                    .fontColor([$r('sys.color.icon_primary')])
            })
                .onClick((): void => {
                    this.onEditRequested(this.row);
                })

            MenuItem({
                content: $r('app.string.menu_delete_connection'),
                symbolStartIcon: new SymbolGlyphModifier($r('sys.symbol.trash'))
                    .fontColor([$r('sys.color.alert')])
            })
                .onClick((): void => {
                    this.onDeleteRequested(this.row);
                })
        }
    }

    /**
     * 行尾控件：选中勾 + 更多入口。菜单在这里用 `bindMenu`（点图标，触屏也有入口），
     * 同时由 HdsListItem 的 `menuStyle` 承接鼠标右键——`MenuStyle.responseType` 只能配一种，
     * 所以两个入口分开挂。
     */
    @Builder
    rowTrailing() {
        Row({ space: 8 }) {
            if (this.isSelected) {
                SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
                    .fontSize(20)
                    .fontColor([$r('sys.color.confirm')])
            }

            SymbolGlyph($r('sys.symbol.ellipsis_circle'))
                .fontSize(20)
                .fontColor([$r('sys.color.icon_secondary')])
                // 图标本身只有 20vp，鼠标/手指容易脱靶；撑到 32vp 命中区。
                .width(32)
                .height(32)
                .accessibilityText($r('app.string.menu_more_actions'))
                .bindMenu(this.rowMenu, HOME_MENU_OPTIONS)
        }
    }

    build() {
        HdsListItem({
            hdsListItemCard: {
                textItem: {
                    primaryText: {
                        text: this.row.connection.name,
                        modifier: this.rowTextModifier,
                    },
                },
                suffixItem: new SuffixCustomBuilder((): void => {
                    this.rowTrailing();
                }),
                // cardWidth 不填百分比：HDS 在 ListItem 交叉轴尺寸确定之前就要这个值，
                // 给 '100%' 实测得到 0，卡片内容直接看不见。
                cardHeight: ROW_HEIGHT,
                // 卡片底色自己定：常态用列表卡面，选中叠一层"激活"半透明色。
                // 想换更重或更淡的选中效果，只改这一行：可选 comp_background_emphasize（强调）、
                // ohos_id_color_emphasize_transparent、comp_background_secondary 等语义色。
                cardBackgroundColor: this.isSelected
                    ? $r('sys.color.ohos_id_color_component_activated_transparent')
                    : $r('sys.color.comp_background_list_card'),
                cardId: this.row.connection.id,
                onClick: (): void => {
                    this.onRowOpen(this.row.connection.id);
                },
            },
            isSelected: this.isSelected,
            // 选中背景本来是画在 ListItem 这一层的，卡片比行窄就露成一圈蓝底；
            // 这一层清空，选中态改画在卡片自己身上（cardBackgroundColor）。
            listItemStateStyles: {
                normalBackgroundColor: Color.Transparent,
                selectedBackgroundColor: Color.Transparent,
            },
            menuStyle: {
                responseType: ResponseType.RightClick,
                menuOptions: HOME_MENU_OPTIONS,
            },
            menuBuilder: this.rowMenu,
            swipeActionOptions: {
                icons: [{
                    icon: new SymbolGlyphModifier($r('sys.symbol.trash')),
                    backgroundColor: $r('sys.color.alert'),
                    onAction: (): void => {
                        this.onDeleteRequested(this.row);
                    },
                }],
            },
        })
    }
}

@ComponentV2
export struct Home {
    @Local private pathStack: NavPathStack = new NavPathStack();
    @Local private selectedConnection: string = '';
    @Local private isFullVpn: boolean = false;
    @Local private navMode: NavigationMode = NavigationMode.Stack;
    @Local private filterKeyword: string = '';
    @Local private groupRows: HomeGroupRow[] = [];
    @Local private isEditSheetShown: boolean = false;
    @Local private editDraft: HomeEditDraft = new HomeEditDraft();
    private configListener: ConfigChangeListener = (): void => {
        this.refreshGroupRows();
    };

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
                    });
            }
        });

        ConfigManager.onChanged(this.configListener);
        this.refreshGroupRows();
    }

    aboutToDisappear(): void {
        ConfigManager.offChanged(this.configListener);
    }

    /**
     * 左列表是 ConfigManager 数据的派生视图：结构变化（新增/删除/移动分组）通过
     * 重新推导这份视图来反映，连接名变化由 @Trace 直接刷新对应行。
     */
    private refreshGroupRows(): void {
        const keyword = this.filterKeyword.trim().toLowerCase();
        const rows: HomeGroupRow[] = [];

        for (const group of Array.from(ConfigManager.allGroups.values())) {
            const connections: HomeConnectionRow[] = [];
            for (const connId of group.connections) {
                const connection = ConfigManager.getConnection(connId);
                if (!connection) {
                    Logger.Warn(TAG, `group ${group.id} references unknown connection ${connId}`);
                    continue;
                }
                if (keyword.length > 0 && connection.name.toLowerCase().indexOf(keyword) < 0) {
                    continue;
                }
                const row: HomeConnectionRow = { connection: connection, groupId: group.id };
                connections.push(row);
            }

            if (keyword.length > 0 && connections.length === 0) {
                continue;
            }

            const groupRow: HomeGroupRow = { id: group.id, name: group.name, connections: connections };
            rows.push(groupRow);
        }

        this.groupRows = rows;
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

    private textOf(name: Resource): string {
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

    private async showFormError(message: ResourceStr): Promise<void> {
        await this.getUIContext()
            .getPromptAction()
            .showDialog({ message: message })
            .catch(() => {
                Logger.Error(TAG, `show dialog failed!`);
            });
    }

    private confirmDeleteConnection(row: HomeConnectionRow): void {
        const title = `${this.textOf($r('app.string.del_title'))}: ${row.connection.name}`;
        this.getUIContext()
            .showAlertDialog({
                title: title,
                message: $r('app.string.del_message'),
                primaryButton: {
                    value: $r('app.string.btn_cancel'),
                    action: (): void => {
                    }
                },
                secondaryButton: {
                    value: $r('app.string.btn_delete'),
                    action: (): void => {
                        this.doDeleteConnection(row);
                    }
                }
            });
    }

    private async doDeleteConnection(row: HomeConnectionRow): Promise<void> {
        const removed = await ConfigManager.removeConnection(row.connection.id);
        if (!removed) {
            await this.showFormError($r('app.string.msg_save_failed'));
            return;
        }

        if (this.selectedConnection === row.connection.id) {
            this.selectedConnection = '';
            if (this.navMode === NavigationMode.Split) {
                // 双栏下右侧不能留空，换成空选中态的详情页。
                this.showDetail('');
            } else if (this.pathStack.size() > 0) {
                this.pathStack.pop();
            }
        }
        this.refreshGroupRows();
    }

    private async openEditSheet(row: HomeConnectionRow): Promise<void> {
        const draft = this.editDraft;
        draft.connId = row.connection.id;
        draft.connName = row.connection.name;
        draft.groupId = row.groupId;
        draft.hostText = '';
        draft.portText = '';
        draft.protocolText = '';
        draft.transportText = '';

        const options: HomeGroupOption[] = [];
        for (const group of Array.from(ConfigManager.allGroups.values())) {
            const option: HomeGroupOption = { id: group.id, name: group.name };
            options.push(option);
        }
        draft.groupOptions = options;

        const root = await ConfigManager.loadConnectionFromFile(row.connection.id);
        if (!root || !root.outbounds || root.outbounds.length === 0) {
            Logger.Error(TAG, `connection ${row.connection.id} has no outbound to edit`);
            await this.showFormError($r('app.string.err_config_unreadable'));
            return;
        }

        const outbound = root.outbounds[0];
        draft.protocolText = outbound.protocol ?? '';
        draft.transportText = outbound.streamSettings?.transport ?? '';
        const settings = outbound.settings;
        if (settings) {
            const address = settings['address'];
            const port = settings['port'];
            draft.hostText = typeof address === 'string' ? address : '';
            if (typeof port === 'number') {
                draft.portText = port.toString();
            } else if (typeof port === 'string') {
                draft.portText = port;
            }
        }

        this.isEditSheetShown = true;
    }

    private async saveEditDraft(): Promise<void> {
        const draft = this.editDraft;
        const connId = draft.connId;
        if (connId.length === 0) {
            this.isEditSheetShown = false;
            return;
        }

        const name = draft.connName.trim();
        if (name.length === 0) {
            await this.showFormError($r('app.string.err_name_required'));
            return;
        }

        const portText = draft.portText.trim();
        if (!Utils.isUnsignedDecimal(portText)) {
            await this.showFormError($r('app.string.err_port_invalid'));
            return;
        }
        const portValue = parseInt(portText);
        if (portValue <= 0 || portValue > MAX_PORT) {
            await this.showFormError($r('app.string.err_port_invalid'));
            return;
        }

        const host = draft.hostText.trim();
        if (host.length === 0) {
            await this.showFormError($r('app.string.err_host_required'));
            return;
        }

        if (!await ConfigManager.renameConnection(connId, name)) {
            await this.showFormError($r('app.string.msg_save_failed'));
            return;
        }

        const currentGroup = ConfigManager.getGroupOfConnection(connId);
        if (!currentGroup || currentGroup.id !== draft.groupId) {
            if (!await ConfigManager.moveConnection(connId, draft.groupId)) {
                await this.showFormError($r('app.string.msg_save_failed'));
                return;
            }
        }

        const root = await ConfigManager.loadConnectionFromFile(connId);
        if (root && root.outbounds && root.outbounds.length > 0) {
            const outbound = root.outbounds[0];
            const protocol = draft.protocolText.trim();
            if (protocol.length > 0) {
                outbound.protocol = protocol;
            }
            if (outbound.settings === undefined) {
                outbound.settings = new JsonObject();
            }
            outbound.settings['address'] = host;
            outbound.settings['port'] = portValue;

            const transport = draft.transportText.trim();
            if (transport.length > 0) {
                if (outbound.streamSettings === undefined) {
                    outbound.streamSettings = new StreamObject();
                }
                outbound.streamSettings.transport = transport;
            }

            if (!await ConfigManager.updateConnectionContent(connId, root)) {
                await this.showFormError($r('app.string.msg_save_failed'));
                return;
            }
        }

        this.isEditSheetShown = false;
        try {
            this.getUIContext()
                .getPromptAction()
                .showToast({ message: $r('app.string.msg_conn_saved') });
        } catch (error) {
            Logger.Error(TAG, `failed to show saved toast: ${JSON.stringify(error)}`);
        }
        this.refreshGroupRows();
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
    groupHeader(groupRow: HomeGroupRow) {
        Row({ space: 8 }) {
            Text(groupRow.name)
                .fontSize(16)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('sys.color.font_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .wordBreak(WordBreak.BREAK_ALL)
                .layoutWeight(1)
            Text(`${groupRow.connections.length}`)
                .fontSize(12)
                .fontColor($r('sys.color.font_tertiary'))
        }
        // 分组用的是 ListItemGroupStyle.NONE，没有系统内边距，组头的左右间距自己给。
        .padding({ left: 8, right: 8 })
        .width('100%')
        .height(GROUP_HEADER_HEIGHT)
    }

    @Builder
    editSheetGroupOptions() {
        Row({ space: 16 }) {
            ForEach(this.editDraft.groupOptions, (option: HomeGroupOption) => {
                Row({ space: 4 }) {
                    Radio({
                        value: option.id,
                        group: MOVE_RADIO_GROUP
                    })
                        .checked(this.editDraft.groupId === option.id)
                        .onChange((isChecked: boolean): void => {
                            if (isChecked) {
                                this.editDraft.groupId = option.id;
                            }
                        })

                    Text(option.name)
                        .fontSize(14)
                }
            }, (option: HomeGroupOption): string => option.id)
        }
        .width('100%')
    }

    @Builder
    editSheet() {
        Column({ space: 12 }) {
            Scroll() {
                Column({ space: 12 }) {
                    HomeEditField({
                        fieldLabel: $r('app.string.field_connection_name'),
                        fieldValue: this.editDraft.connName,
                        onFieldValue: (value: string): void => {
                            this.editDraft.connName = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_host'),
                        fieldValue: this.editDraft.hostText,
                        onFieldValue: (value: string): void => {
                            this.editDraft.hostText = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_port'),
                        fieldValue: this.editDraft.portText,
                        numericInput: true,
                        onFieldValue: (value: string): void => {
                            this.editDraft.portText = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_protocol'),
                        fieldValue: this.editDraft.protocolText,
                        onFieldValue: (value: string): void => {
                            this.editDraft.protocolText = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_transport'),
                        fieldValue: this.editDraft.transportText,
                        onFieldValue: (value: string): void => {
                            this.editDraft.transportText = value;
                        },
                    })

                    Text($r('app.string.field_group'))
                        .fontSize(13)
                        .fontColor($r('sys.color.font_secondary'))

                    this.editSheetGroupOptions();
                }
                .width('100%')
            }
            .layoutWeight(1)
            .width('100%')

            Row({ space: 8 }) {
                Button($r('app.string.btn_cancel'))
                    .layoutWeight(1)
                    .onClick((): void => {
                        this.isEditSheetShown = false;
                    })

                Button($r('app.string.btn_save'))
                    .layoutWeight(1)
                    .onClick((): void => {
                        this.saveEditDraft();
                    })
            }
            .width('100%')
        }
        .padding(16)
        .width('100%')
        .height('100%')
    }

    @Builder
    addSomethingButton() {
        Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus'))
                .fontColor([$r('sys.color.font_on_primary')])
                .fontSize(24)
        }
        .backgroundColor($r('sys.color.brand'))
        .width(48)
        .height(48)
    }

    build() {
        Navigation(this.pathStack) {
            Column({ space: 4 }) {
                this.kernelStatusSummary();

                Search({ placeholder: $r('app.string.list_search_hint'), value: this.filterKeyword })
                    .width('100%')
                    .onChange((value: string): void => {
                        this.filterKeyword = value;
                        this.refreshGroupRows();
                    })
                    .onSubmit((value: string): void => {
                        this.filterKeyword = value;
                        this.refreshGroupRows();
                    })

                if (this.groupRows.length === 0) {
                    Text($r('app.string.list_empty_hint'))
                        .fontSize(13)
                        .fontColor($r('sys.color.font_tertiary'))
                        .padding(8)
                }

                // 分组列表：组头吸顶。分组本身不用 ListItemGroupStyle.CARD——HdsListItemCard 已经
                // 是卡片了，再套一层分组卡就会出现两层外框和双重内边距。
                List({ space: GROUP_SECTION_SPACING }) {
                    Repeat(this.groupRows)
                        .each((groupItem: RepeatItem<HomeGroupRow>) => {
                            ListItemGroup({
                                header: this.groupHeader(groupItem.item),
                                space: GROUP_ITEM_SPACING,
                                style: ListItemGroupStyle.NONE
                            }) {
                                Repeat(groupItem.item.connections)
                                    .each((connectionItem: RepeatItem<HomeConnectionRow>) => {
                                        HomeConnectionListItem({
                                            row: connectionItem.item,
                                            isSelected: this.selectedConnection === connectionItem.item.connection.id,
                                            onRowOpen: (connectionId: string): void => {
                                                this.showDetail(connectionId);
                                            },
                                            onEditRequested: (row: HomeConnectionRow): void => {
                                                this.openEditSheet(row);
                                            },
                                            onDeleteRequested: (row: HomeConnectionRow): void => {
                                                this.confirmDeleteConnection(row);
                                            },
                                        })
                                    })
                                    .key((item: HomeConnectionRow): string => item.connection.id)
                            }
                        })
                        .key((item: HomeGroupRow): string => item.id)
                }
                .sticky(StickyStyle.Header)
                .layoutWeight(1)

                Row() {
                    this.addSomethingButton();
                }
                .hitTestBehavior(HitTestMode.Transparent)
                .justifyContent(FlexAlign.Center)
                .width('100%')
                .position({ bottom: '20vp' })
            }
            .backgroundColor($r('sys.color.background_secondary'))
            .padding(8)
            .width('100%')
            .height('100%')
            .bindSheet($$this.isEditSheetShown, this.editSheet, {
                detents: [SheetSize.MEDIUM, SheetSize.LARGE],
                dragBar: true,
                showClose: true,
                title: { title: $r('app.string.sheet_edit_title') }
            })
        }
        .navDestination(this.detailPageMap)
        .mode(NavigationMode.Auto)
        .navBarWidth(NAV_BAR_WIDTH)
        // 只设 navBarWidth 时分割线不可拖；给了区间就能拖拽调宽（双栏模式生效）。
        .navBarWidthRange([NAV_BAR_MIN_WIDTH, NAV_BAR_MAX_WIDTH])
        .minContentWidth(MIN_CONTENT_WIDTH)
        .hideTitleBar(true)
        .onNavigationModeChange((mode: NavigationMode): void => {
            this.onNavigationModeChanged(mode);
        })
        .width('100%')
        .height('100%')
    }
}
