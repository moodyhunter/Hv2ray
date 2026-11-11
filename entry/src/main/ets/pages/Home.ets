import { KernelEvent, KernelEventType, Utils } from '../utils/Common';
import { CommonEventUtils } from '../utils/CommonEventUtils';
import { GlobalKernelStatus, kernelStatusColor, kernelStatusLabel } from './PageCommon';
import { ConfigManager, ConfigChangeListener } from '../core/config/ConfigManager';
import { StreamObject } from '../core/config/Config';
import { JsonObject } from '../core/config/ConfigDefs';
import { HomeConnectionDetail } from './components/HomeDetail';
import { HomeConnectionListItem } from './components/HomeListRow';
import { HomeEditDraft, HomeEditSheetForm } from './components/HomeEditSheet';
import {
    GROUP_HEADER_HEIGHT,
    GROUP_ITEM_SPACING,
    GROUP_SECTION_SPACING,
    HomeConnectionRow,
    HomeGroupOption,
    HomeGroupRow,
    stopKernel
} from './components/HomeCommon';
import Logger from '../utils/Logging';

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

const MAX_PORT = 65535;

interface HomeDetailParam {
    connectionIdValue: string;
}

/**
 * 左列（分组 + 连接）与导航壳。其余几块在 pages/components/ 下：
 * - 一行连接怎么画：components/HomeListRow.ets
 * - 详情区（状态、流量、启停）：components/HomeDetail.ets
 * - 编辑半模态的表单：components/HomeEditSheet.ets
 * - 派生视图类型、行尺寸、行菜单参数、停止内核：components/HomeCommon.ets
 * 这里留下的是：数据到派生视图的推导、增删改与校验、导航与分栏。
 */
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
    editSheet() {
        HomeEditSheetForm({
            draft: this.editDraft,
            onSave: (): void => {
                this.saveEditDraft();
            },
            onCancel: (): void => {
                this.isEditSheetShown = false;
            },
        })
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
