import { LengthMetrics } from '@kit.ArkUI';
import Logger from '../utils/Logging';
import Hv2rayPreferences from '../utils/Preferences';

const TAG = "Hv2ray-Settings"

@ComponentV2
export struct Settings {
    @Local private configuration: string = "";

    aboutToAppear(): void {
        this.configuration = Hv2rayPreferences.GetConfig(this.getUIContext().getHostContext()!);
    }

    build() {
        Column({ space: 16 }) {
            Text(`Socks5 Port ${Hv2rayPreferences.GetSocks5Port(getContext(this))}`)
                .fontSize(16)
                .width('100%')
                .textAlign(TextAlign.Start)

            TextArea({ text: this.configuration!! })
                .width('100%')
                .height(650)
                .flexGrow(1)
                .layoutWeight(1)

            Row ({ space: 16 }) {
                Button("Save")
                    .onClick(async () => {
                        Hv2rayPreferences.SetConfig(getContext(this), this.configuration);
                        this.getUIContext().getPromptAction().showToast({ message: `Configuration saved`, duration: 2000 })
                    })

                Button('Format')
                    .onClick(() => {
                        try {
                            let object: object = JSON.parse(this.configuration);
                            this.configuration = JSON.stringify(object, undefined, 4);
                        } catch (e) {
                            Logger.Error(TAG, `json is invalid`);
                            this.getUIContext().getPromptAction().showToast({ message: 'JSON invalid' });
                        }
                    })
            }
        }
        .margin(10)
    }
}