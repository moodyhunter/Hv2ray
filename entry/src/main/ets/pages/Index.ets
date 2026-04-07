import { Home } from './Home';
import Logger from '../utils/Logging';
import { Settings } from './Settings';
import { Configurations } from './Configurations';
import { GlobalStat } from './PageCommon';

const TAG = "Hv2ray-Index"

@Entry
@ComponentV2
struct Index {
    aboutToAppear(): void {
        Logger.Info(TAG, `aboutToAppear`);
    }

    build() {
        Column() {
            Row() {
                Text('Hv2ray')
                    .fontSize(20)
                    .fontWeight(FontWeight.Bold)
                Text('↑  ' + GlobalStat.txRateString + '\n' + '↓  ' + GlobalStat.rxRateString)
                    .fontSize(13)
                    .width(100)
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
