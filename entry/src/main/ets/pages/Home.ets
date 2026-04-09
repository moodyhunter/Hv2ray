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
import { IConnection, IGroup } from '../core/config/ConfigCommon';
import { ConfigManager } from '../core/config/ConfigManager';
import { ConfigRoot, Inbound } from '../core/config/Config';


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

@ObservedV2
class ConnectionInfo {
    private readonly connId: string;
    public readonly config: ConfigRoot;
    @Trace connectionName: string;
    @Trace remoteHost: string;
    @Trace remotePort: number;
    @Trace protocol: string;
    @Trace transport: string;

    constructor(connId: string, root: ConfigRoot) {
        this.connId = connId;
        this.config = root;
        this.connectionName = ConfigManager.getConnection(connId)?.name ?? "<invalid>";
        this.remoteHost = root.outbounds[0].settings['address'] as string;
        this.remotePort = root.outbounds[0].settings['port'] as number;
        this.protocol = root.outbounds[0].protocol;
        this.transport = root.outbounds[0].streamSettings.transport;
    }

    static async getConnectionInfo(connId: string): Promise<ConnectionInfo> {
        const root = (await ConfigManager.loadConnectionFromFile(connId))!;
        return new ConnectionInfo(connId, root);
    }
}


@ComponentV2
export struct Home {
    @Local kernelStatus: KernelEventType = KernelEventType.Stopped;
    @Local selectedConnection: string = '';
    @Local connectionInfo: ConnectionInfo | undefined = undefined;

    @Monitor('selectedConnection')
    async onSelectedConnectionChanged() {
        this.connectionInfo = await ConnectionInfo.getConnectionInfo(this.selectedConnection);
    }

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

    private getCurrentConfig(port: number): string {
        if (!this.connectionInfo) {
            return '';
        }
        const configRoot: ConfigRoot = JSON.parse(JSON.stringify(this.connectionInfo.config));
        const socks5Inbound: Inbound = {
            listen: '127.0.0.1',
            port: port.toString(),
            settings: {
                'udpEnabled': true,
            },
            protocol: 'socks',
            tag: 'default-inbound',
            sniffing: undefined,
        };
        configRoot.inbounds.push(socks5Inbound);

        const configRootObject = configRoot as object as Record<string, object>;

        return JSON.stringify(configRootObject);
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

        const socks5Port = Hv2rayPreferences.GetSocks5Port(context);
        let want: Want = {
            bundleName: BUNDLE_NAME,
            abilityName: 'VpnAbility',
            parameters: {
                'socks5Port': socks5Port,
            }
        };

        const ret = VCoreManager.StartVCore(socks5Port, this.getCurrentConfig(socks5Port));
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

    @Builder
    kernelStatusIcon() {
        Circle()
            .width(100)
            .height(100)
            .foregroundColor(this.kernelStatusColor)
    }

    @Builder
    statusComponent() {
        Row({ space: 32 }) {
            this.kernelStatusIcon()
            Text(KernelEventType[this.kernelStatus])
                .fontSize(40)
                .fontWeight(FontWeight.Bold)
        }
    }

    @Builder
    controlButtons() {
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

    @Builder
    selectedConnectionInfo() {
        Column() {
            if (this.connectionInfo) {
                Text(this.connectionInfo.connectionName)
                    .fontSize(30)
                    .fontWeight(FontWeight.Bold)
                Text(this.connectionInfo.remoteHost + ':' + this.connectionInfo.remotePort)
                    .fontWeight(FontWeight.Bold)
                Text(this.connectionInfo.protocol + '/' + this.connectionInfo.transport)
            } else {
                Text('None selected')
            }
        }
        .width('100%')
        .margin({ bottom: 50 })
    }

    @Builder
    connectionItem(conn: IConnection | undefined) {
        Row() {
            if (conn) {
                Button(conn.name)
                    .width('100%')
                    .onClick(() => {
                        this.selectedConnection = conn.id;
                    })
                    .backgroundColor(this.selectedConnection === conn.id ? Color.Red : undefined)
            } else {
                Text('invalid')
            }
        }
        .width('100%')
    }

    @Builder
    groupItem(group: IGroup) {
        Column() {
            Row() {
                Text(group.name)
                    .fontSize(18)
                    .fontWeight(FontWeight.Bold)
                    .margin({ left: 8 })
                Button('Edit')
            }
            .borderRadius(8)
            .padding(8)
            .justifyContent(FlexAlign.SpaceBetween)
            .backgroundColor($r('sys.color.gray_03'))
            .height(48)
            .width('100%')

            List({ space: 16 }) {
                ForEach(group.connections, (connId: string) => {
                    ListItem() {
                        this.connectionItem(ConfigManager.getConnection(connId));
                    }
                }, (connId: string) => connId)
            }
            .padding({ left: 8, right: 8 })
            .width('100%')
            .height(300)
        }
    }

    @Builder
    addSomethingButton() {
        Button({ type: ButtonType.Circle }) {
            SymbolGlyph($r('sys.symbol.plus'))
                .fontColor([$r('sys.color.font_primary')])
                .fontSize(24)
        }
        .backgroundColor($r('sys.color.brand'))
        .width(48)
        .height(48)
    }

    build() {
        Row() {
            Column() {
                // list all groups
                List({ space: 8 }) {
                    ForEach(Array.from(ConfigManager.allGroups.values()), (group: IGroup) => {
                        ListItem() {
                            this.groupItem(group);
                        }
                    }, (group: IGroup) => group.id)
                }
                .backgroundColor($r('sys.color.gray_02'))
                .padding(8)
                .width('100%')
                .height('100%')

                Row() {
                    this.addSomethingButton();
                }
                .hitTestBehavior(HitTestMode.Transparent)
                .justifyContent(FlexAlign.Center)
                .width('100%')
                .position({ bottom: '20vp' })
            } 
            .width(350)
            .constraintSize({ minWidth: 300 })
            .height('100%')

            Column({ space: 40 }) {
                this.selectedConnectionInfo();
                this.statusComponent();
                this.speedStats();
                this.controlButtons();
            }
            .padding(16)
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .height('100%')
        }
        .height('100%')
        .width('100%')
    }
}