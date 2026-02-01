import { Want } from '@kit.AbilityKit';
import { vpnExtension } from '@kit.NetworkKit';
import { commonEventManager } from '@kit.BasicServicesKit';
import Logging from '../utils/Logging';
import { Constants, Stat } from '../utils/Common';
import Hv2rayPreferences from '../utils/Preferences';
import { LengthMetrics, promptAction } from '@kit.ArkUI';

const TAG = "Hv2ray-Index"

let want: Want = {
    bundleName: "me.moody.hv2ray",
    abilityName: "VpnAbility",
};

let subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
    events: [Constants.EVENT_NAME],
};

let subscriber: commonEventManager.CommonEventSubscriber;

function prettyPrintBytes(bytes: number): string {
    if (bytes === 0) {
        return "0 B";
    }

    const k = 1024;
    const dm = 2;
    const units = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    for (let i = 0; i < units.length; i++) {
        if (bytes < k) {
            return bytes.toFixed(dm) + " " + units[i];
        }
        bytes /= k;
    }

    return bytes.toFixed(dm) + " " + units[units.length - 1];
}

@Entry
@Component
struct Index {
    @State rx_rate: number = 0;
    @State tx_rate: number = 0;
    @State configuration: string = "";

    onStatisticsData(data: string) {
        let dataObj: Stat = JSON.parse(data);
        this.rx_rate = dataObj.rx;
        this.tx_rate = dataObj.tx;
        Logging.Info(TAG, `rx: ${this.rx_rate}, tx: ${this.tx_rate}`);
    }

    async onDidBuild() {
        subscriber = await commonEventManager.createSubscriber(subscribeInfo);
        if (!subscriber) {
            Logging.Error(TAG, `Failed to create common event subscriber`);
            return;
        }

        commonEventManager.subscribe(subscriber, (err, commonEvent: commonEventManager.CommonEventData) => {
            if (err) {
                Logging.Error(TAG, `Failed to subscribe common event. ${err.code}, ${err.message}`);
                return;
            }

            Logging.Debug(TAG, `Received common event: ${JSON.stringify(commonEvent)}`);
            if (!commonEvent.data) {
                Logging.Warn(TAG, `No data in common event`);
                return;
            }

            this.onStatisticsData(commonEvent.data);
        })

        this.configuration = Hv2rayPreferences.GetConfig(getContext(this));
    }

    build() {
        Tabs({ barPosition: BarPosition.End }) {
            TabContent() {
                Row() {
                    Column() {
                        Text("VPN Extension")
                            .fontSize(40)
                            .fontWeight(FontWeight.Bold)
                            .margin({ bottom: 30 })

                        Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween }) {
                            Text("Upload:")
                                .fontSize(20)
                                .width(150)
                                .fontWeight(FontWeight.Bold)

                            Text(prettyPrintBytes(this.tx_rate) + "/s")
                                .fontSize(20)
                                .fontWeight(FontWeight.Bold)
                                .textAlign(TextAlign.End)
                                .border({ width: 1, color: Color.Black })
                        }
                        .margin({ bottom: 10 })
                        .width('70%')

                        Flex({ direction: FlexDirection.Row, justifyContent: FlexAlign.SpaceBetween }) {
                            Text("Download:")
                                .fontSize(20)
                                .width(150)
                                .fontWeight(FontWeight.Bold)

                            Text(prettyPrintBytes(this.rx_rate) + "/s")
                                .fontSize(20)
                                .fontWeight(FontWeight.Bold)
                                .textAlign(TextAlign.End)
                                .border({ width: 1, color: Color.Black })
                        }
                        .margin({ bottom: 50 })
                        .width('70%')

                        Button("Start")
                            .fontSize(30)
                            .fontWeight(FontWeight.Bold)
                            .backgroundColor(Color.Green)
                            .padding(20)
                            .width(150)
                            .margin({ bottom: 30 })
                            .onClick(async () => {
                                Logging.Info(TAG, `onStart`);
                                // verify if JSON is valid
                                let config = Hv2rayPreferences.GetConfig(getContext(this));
                                try {
                                    JSON.parse(config);
                                } catch (e) {
                                    promptAction.showToast({ message: `Invalid JSON configuration`, duration: 2000 })
                                    return;
                                }
                                try {
                                    await vpnExtension.startVpnExtensionAbility(want);
                                } catch (e) {
                                    Logging.Error(TAG, `failed to start VpnAbility: ${JSON.stringify(e)}`);
                                }
                                Logging.Info(TAG, `onStart done`);
                            })

                        Button("Stop")
                            .fontSize(30)
                            .fontWeight(FontWeight.Bold)
                            .backgroundColor(Color.Red)
                            .padding(20)
                            .width(150)
                            .onClick(async () => {
                                await vpnExtension.stopVpnExtensionAbility(want);
                            })
                    }
                    .width('100%')
                }
                .height('100%')
            }
            .tabBar('Home')

            TabContent() {
                Flex({
                    direction: FlexDirection.Column,
                    space: { main: LengthMetrics.px(20) },
                    alignItems: ItemAlign.Center
                }) {
                    Text(`Socks5 Port ${Hv2rayPreferences.GetSocks5Port(getContext(this))}`)
                        .fontSize(16)
                        .width('100%')
                        .textAlign(TextAlign.Start)

                    TextArea({ text: this.configuration })
                        .width('100%')
                        .height(650)
                        .onChange((text) => {
                            this.configuration = text;
                        })

                    Button("Save")
                        .onClick(async () => {
                            Hv2rayPreferences.SetConfig(getContext(this), this.configuration);
                            promptAction.showToast({ message: `Configuration saved`, duration: 2000 })
                        })
                }
                .margin(10)
            }
            .tabBar('Configuration')
        }
        .width('100%')
        .height('100%')
        .barHeight(45)
    }
}
