import { Home } from './Home';
import Logger from '../utils/Logging';
import { Settings } from './Settings';
import { Configurations } from './Configurations';

const TAG = "Hv2ray-Index"

@Entry
@ComponentV2
struct Index {
    aboutToAppear(): void {
        Logger.Info(TAG, `aboutToAppear`);
    }

    build() {
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
        .width('100%')
        .height('100%') 
        .vertical(true)
        .barWidth(80)
    }
}
