import { SymbolGlyphModifier, TextModifier } from '@kit.ArkUI';
import { HdsListItem, SuffixCustomBuilder } from '@kit.UIDesignKit';
import { HOME_MENU_OPTIONS, HomeConnectionRow, ROW_HEIGHT } from './HomeCommon';

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
export struct HomeConnectionListItem {
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
