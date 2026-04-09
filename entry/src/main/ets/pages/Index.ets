import { Home } from './Home';
import Logger from '../utils/Logging';
import { Settings } from './Settings';
import { Configurations } from './Configurations';
import { GlobalStat } from './PageCommon';
import common from '@ohos.app.ability.common';

const TAG = "Hv2ray-Index"

@Entry
@ComponentV2
struct Index {
    private readonly uiAbilityContext = this.getUIContext()
        .getHostContext() as common.UIAbilityContext;
    private readonly window = this.uiAbilityContext.windowStage.getMainWindowSync();
    @Local private isTopMost: boolean = false;

    aboutToAppear(): void {
        Logger.Info(TAG, `aboutToAppear`);
    }

    build() {
        Column() {
            Row() {
                Text('Hv2ray')
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)


                Row() {
                    Text('↑  ' + GlobalStat.txRateString + '\n' + '↓  ' + GlobalStat.rxRateString)
                        .fontSize(13)
                        .width(100)

                    Button('T', { type: ButtonType.Circle })
                        .onClick(() => {
                            this.isTopMost = !this.isTopMost;
                            this.window.setWindowTopmost(this.isTopMost);
                        })
                        .buttonStyle(this.isTopMost ? ButtonStyleMode.EMPHASIZED : ButtonStyleMode.NORMAL)
                }
            }
            .justifyContent(FlexAlign.SpaceBetween)
            .height(60)
            .width('100%')
            .padding({ left: 24, right: 160 })

            Tabs({ barPosition: BarPosition.Start }) {
                TabContent() {
                    Home()
                }
                .tabBar('Home')

                TabContent() {
                    Configurations()
                }
                .tabBar('Config')

                TabContent() {
                    Settings()
                }
                .tabBar('Settings')
            }
            .layoutWeight(1)
            .vertical(true)
            .barWidth(80)
        }
        .width('100%')
        .height('100%')
    }
}
