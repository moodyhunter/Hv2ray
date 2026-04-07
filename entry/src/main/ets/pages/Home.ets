import { vpnExtension } from '@kit.NetworkKit';
import { KernelEvent, KernelEventType } from '../utils/Common';
import Logger from '../utils/Logging';
import { Want } from '@kit.AbilityKit';
import { BUNDLE_NAME } from 'BuildProfile';
import fs from '@ohos.file.fs';
import Hv2rayPreferences from '../utils/Preferences';
import { CommonEventUtils } from '../utils/CommonEventUtils';
import { GlobalStat, prettyPrintBytes } from './PageCommon'
import { VCoreManager } from '../vpn/VCoreManager';


const TAG = "Hv2ray-HomePage"

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

    async aboutToAppear() {
        CommonEventUtils.subscribeKernelEvent(async (kernelEvent: KernelEvent) => {
            this.kernelStatus = kernelEvent.type;
            if (kernelEvent.type === KernelEventType.Crashed) {
                await this.getUIContext()
                    .getPromptAction()
                    .showDialog({
                        message: kernelEvent.message.join('\n')
                    })     
                    .catch(() => {
                        Logger.Error(TAG, `show dialog failed!`);
                    })
            }
        });
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

        let want: Want = {
            bundleName: BUNDLE_NAME,
            abilityName: 'VpnAbility',
            parameters: {
                'socks5Port': Hv2rayPreferences.GetSocks5Port(context),
            }
        };

        const ret = VCoreManager.StartVCore(Hv2rayPreferences.GetSocks5Port(context), Hv2rayPreferences.GetConfig(context));
        if (!ret) {
            return;
        }

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
            SpeedStatsRow({ message: 'Upload', value: GlobalStat.txRate, suffix: '/s' })
            SpeedStatsRow({ message: 'Download', value: GlobalStat.rxRate, suffix: '/s' })
            SpeedStatsRow({ message: 'Total Upload', value: GlobalStat.txTotal })
            SpeedStatsRow({ message: 'Total Download', value: GlobalStat.rxTotal })
        }
    }

    build() {
        Column({ space: 40 }) {
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

            Row({ space: 30 }) {
                Button(this.kernelStatus === KernelEventType.Started ? 'Restart' : 'Start')
                    .fontSize(30)
                    .fontWeight(FontWeight.Bold)
                    .backgroundColor(Color.Green)
                    .padding(20)
                    .width(150)
                    .onClick(async () => {
                        Logger.Info(TAG, `onStart`);
                        const currentStatus = this.kernelStatus;
                        VCoreManager.StopVCore();
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

                if (this.kernelStatus === KernelEventType.Started) {
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
        }
        .height('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
    }
}