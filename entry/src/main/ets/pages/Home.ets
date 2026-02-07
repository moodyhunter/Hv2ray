import { vpnExtension } from '@kit.NetworkKit';
import { Constants, KernelEvent, KernelEventType, Stat } from '../utils/Common';
import Logger from '../utils/Logging';
import { commonEventManager } from '@kit.BasicServicesKit';
import { Want } from '@kit.AbilityKit';
import { BUNDLE_NAME } from 'BuildProfile';
import fs from '@ohos.file.fs';
import Hv2rayPreferences from '../utils/Preferences';
import { CommonEventUtils } from '../utils/CommonEventUtils';

const TAG = "Hv2ray-HomePage"

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

@ObservedV2
class GuiStatObject {
    @Trace rxRate: number = 0;
    @Trace txRate: number = 0;
    @Trace rxTotal: number = 0;
    @Trace txTotal: number = 0;
}

const statObject = new GuiStatObject();

@ComponentV2
struct SpeedStatsRow {
    @Require @Param message: string;
    @Require @Param value: number;
    @Param suffix: string = '';

    build() {
        Row() {
            Text(this.message)
                .fontSize(20)
                .width(150)
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


@ComponentV2
export struct Home {
    @Local kernelStatus: KernelEventType = KernelEventType.Stopped;

    private get kernelStatusColor(): Color {
        switch (this.kernelStatus) {
            case KernelEventType.Starting: return Color.Yellow;
            case KernelEventType.Started: return Color.Green;
            case KernelEventType.Crashed: return Color.Red;
            case KernelEventType.Stopped: return Color.Blue;
        }
    }

    onStatisticsData(dataObj: Stat) {
        statObject.rxRate = dataObj.rx;
        statObject.txRate = dataObj.tx;
        statObject.rxTotal += statObject.rxRate;
        statObject.txTotal += statObject.txRate;
    }

    async aboutToAppear() {
        CommonEventUtils.subscribeStatsEvent((stat: Stat) => {
            this.onStatisticsData(stat);
        });

        CommonEventUtils.subscribeKernelEvent(async (kernelEvent: KernelEvent) => {
            this.kernelStatus = kernelEvent.type;
            if (kernelEvent.type === KernelEventType.Crashed) {
                await this.getUIContext()
                    .getPromptAction()
                    .showDialog({
                        message: kernelEvent.message.join('\n\n')
                    })     
                    .catch(() => {
                        Logger.Error(TAG, `show dialog failed!`);
                    })
            }
        });
    }

    @Builder
    speedStats() {
        Column({ space: 10 }) {
            SpeedStatsRow({ message: 'Upload', value: statObject.txRate, suffix: '/s' })
            SpeedStatsRow({ message: 'Download', value: statObject.rxRate, suffix: '/s' })
            SpeedStatsRow({ message: 'Total Upload', value: statObject.txTotal })
            SpeedStatsRow({ message: 'Total Download', value: statObject.rxTotal })
        }
    }

    build() {
        Column({ space: 40 }) {
            Text('Hv2ray')
                .fontSize(40)
                .fontWeight(FontWeight.Bold)

            Row({ space: 32 }) {
                Circle()
                    .width(100)
                    .height(100)
                    .foregroundColor(this.kernelStatusColor)

                Text(KernelEventType[this.kernelStatus])
                    .fontSize(40)
                    .fontWeight(FontWeight.Bold)
            }

            this.speedStats();

            Column({ space: 30 }) {
                Button("Start")
                    .fontSize(30)
                    .fontWeight(FontWeight.Bold)
                    .backgroundColor(Color.Green)
                    .padding(20)
                    .width(150)
                    .onClick(async () => {
                        Logger.Info(TAG, `onStart`);
                        // verify if JSON is valid
                        let config = Hv2rayPreferences.GetConfig(this.getUIContext().getHostContext()!);
                        try {
                            JSON.parse(config);
                        } catch (e) {
                            this.getUIContext().getPromptAction().showToast({ message: `Invalid JSON configuration`, duration: 2000 })
                            return;
                        }

                        const fileDir = this.getUIContext().getHostContext()!.getApplicationContext().filesDir;
                        Logger.Info(TAG, `fileDir: '${fileDir}'`);

                        try {
                            fs.unlinkSync(fileDir + '/' + 'error.log');
                        } catch (e) {
                            Logger.Error(
                                TAG,
                                `failed to remove file:${JSON.stringify(e)}`
                            );
                        }

                        try {
                            fs.unlinkSync(fileDir + '/' + 'access.log');
                        } catch (e) {
                            Logger.Error(
                                TAG,
                                `failed to remove file:${JSON.stringify(e)}`
                            );
                        }

                        let want: Want = {
                            bundleName: BUNDLE_NAME,
                            abilityName: 'VpnAbility',
                            parameters: {
                                'config': config,
                                'socks5Port': Hv2rayPreferences.GetSocks5Port(this.getUIContext().getHostContext()!),
                            }
                        };

                        try {
                            await vpnExtension.startVpnExtensionAbility(want);
                        } catch (e) {
                            Logger.Error(TAG, `failed to start VpnAbility: ${JSON.stringify(e)}`);
                        }
                        Logger.Info(TAG, `onStart done`);
                    })

                Button("Stop")
                    .fontSize(30)
                    .fontWeight(FontWeight.Bold)
                    .backgroundColor(Color.Red)
                    .padding(20)
                    .width(150)
                    .onClick(async () => {
                        try {
                            await vpnExtension.stopVpnExtensionAbility({
                                bundleName: BUNDLE_NAME,
                                abilityName: 'VpnAbility',
                            });
                        } catch (error) {
                            Logger.Error(TAG, `failed to stop VpnAbility: ${JSON.stringify(error)}`);
                        }
                    })
            }
        }
        .height('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
    }
}