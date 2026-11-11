import { Home } from './Home';
import Logger from '../utils/Logging';
import { Settings } from './Settings';
import { Configurations } from './Configurations';
import { GlobalStat } from './PageCommon';
import common from '@ohos.app.ability.common';
import { mediaquery } from '@kit.ArkUI';

const TAG = "Hv2ray-Index"

/** 窄屏判定，阈值与系统横向断点 sm/md 分界（600vp）一致 */
const NARROW_QUERY = '(width < 600vp)';
/** 宽屏侧边标签栏宽度；窄屏用横向底部标签栏，取默认占比 */
const SIDE_BAR_WIDTH = 80;
/** 宽屏顶栏右侧留白，给窗口控件按钮让位（窄屏无窗口装饰） */
const HEADER_RIGHT_PADDING_WIDE = 160;
const HEADER_PADDING_HORIZONTAL = 16;

@Entry
@ComponentV2
struct Index {
    private readonly uiAbilityContext = this.getUIContext()
        .getHostContext() as common.UIAbilityContext;
    private readonly window = this.uiAbilityContext.windowStage.getMainWindowSync();
    @Local private isTopMost: boolean = false;
    @Local private isNarrow: boolean = false;
    private narrowListener: mediaquery.MediaQueryListener | undefined = undefined;

    aboutToAppear(): void {
        Logger.Info(TAG, `aboutToAppear`);

        const listener = this.getUIContext()
            .getMediaQuery()
            .matchMediaSync(NARROW_QUERY);
        this.narrowListener = listener;
        this.isNarrow = listener.matches;
        listener.on('change', (result: mediaquery.MediaQueryResult): void => {
            Logger.Info(TAG, `narrow screen: ${result.matches}`);
            this.isNarrow = result.matches;
        });
    }

    aboutToDisappear(): void {
        this.narrowListener?.off('change');
        this.narrowListener = undefined;
    }

    build() {
        Column() {
            Row({ space: 8 }) {
                Text('Hv2ray')
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)

                Row({ space: 8 }) {
                    Text('↑  ' + GlobalStat.txRateString + '\n' + '↓  ' + GlobalStat.rxRateString)
                        .fontSize(this.isNarrow ? 11 : 13)
                        .textAlign(TextAlign.End)
                        .maxLines(2)

                    if (!this.isNarrow) {
                        Button('T', { type: ButtonType.Circle })
                            .onClick(() => {
                                this.isTopMost = !this.isTopMost;
                                this.window.setWindowTopmost(this.isTopMost);
                            })
                            .buttonStyle(this.isTopMost ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
                    }
                }
                .layoutWeight(1)
                .justifyContent(FlexAlign.End)
            }
            .justifyContent(FlexAlign.SpaceBetween)
            .height(60)
            .width('100%')
            .padding({ left: HEADER_PADDING_HORIZONTAL, right: this.isNarrow ? HEADER_PADDING_HORIZONTAL : HEADER_RIGHT_PADDING_WIDE })

            Tabs() {
                TabContent() {
                    Home()
                }
                .tabBar($r('app.string.tab_home'))

                TabContent() {
                    Configurations()
                }
                .tabBar($r('app.string.tab_config'))

                TabContent() {
                    Settings()
                }
                .tabBar($r('app.string.tab_settings'))
            }
            .layoutWeight(1)
            .barPosition(this.isNarrow ? BarPosition.End : BarPosition.Start)
            .vertical(!this.isNarrow)
            .barWidth(this.isNarrow ? '100%' : SIDE_BAR_WIDTH)
        }
        .width('100%')
        .height('100%')
    }
}
