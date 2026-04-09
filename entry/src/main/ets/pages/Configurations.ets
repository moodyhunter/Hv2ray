import { http } from "@kit.NetworkKit";
import Logger from "../utils/Logging";
import { IShareLinkImporter, IShareLinkImporterResult } from "../core/sharelink/ShareLinkIO";
import { VMessShareLinkImporter } from "../core/sharelink/VMess";
import { Utils } from "../utils/Common";
import { ConfigManager } from "../core/config/ConfigManager";
import { ConfigRoot } from "../core/config/Config";

const TAG = 'Pages/Configuration';

const SHARE_LINK_IMPORTERS: IShareLinkImporter[] = [
    new VMessShareLinkImporter()
];

@ComponentV2
export struct Configurations {
    @Local private subscriptionLink: string = 'http://127.0.0.1:8000/sub.txt';
    @Local private subscriptionContent: string[] = [];
    @Local private decoded: string[] = [];
    @Local private useProxy: boolean = false;

    aboutToAppear(): void {

    }

    private async doGetSubscriptionData(): Promise<void> {
        try {
            const req = http.createHttp();
            let options: http.HttpRequestOptions = {
                // usingProxy: {
                // host: '127.0.0.1',
                // port: 12345,
                // exclusionList: []
                // }
            };
            let response = await req.request(this.subscriptionLink, options);
            const decoded = Utils.base64Decode(response.result as string);
            this.subscriptionContent = decoded.split('\n');
        } catch (e) {
            Logger.Error(TAG, `error: ${JSON.stringify(e)}`);
        }
    }

    private decode() {
        for (const line of this.subscriptionContent) {
            const item = this.decodeOne(line);
            if (item) {
                this.decoded.push(JSON.stringify(item));

                let configRoot: ConfigRoot = {
                    inbounds: [],
                    outbounds: [
                        item.outbound
                    ]
                };
                ConfigManager.addConnectionToGroup(item.name, 'subscription', configRoot)
            }
        }
    }

    private decodeOne(uri: string): IShareLinkImporterResult | undefined {
        for (let importer of SHARE_LINK_IMPORTERS) {
            if (importer.matcher(uri)) {
                const imported = importer.decode(uri);
                if (imported) {
                    return imported;
                }
            }
        }

        Logger.Error(TAG, `failed to import ${uri}`);
        return undefined;
    }

    @Builder
    useProxyCheckbox() {
        Row() {
            Checkbox()
                .select(this.useProxy!!)
            Text('Use Proxy')
        }
    }

    build() {
        Column({ space: 16 }) {
            Row ({ space: 8 }) {
                TextInput({ placeholder: 'subscription link', text: this.subscriptionLink!! })
                    .height('100%')
                    .layoutWeight(1)

                this.useProxyCheckbox();
                Button('GET')
                    .onClick(async () => {
                        Logger.Warn(TAG, `GET using proxy: ${this.useProxy}`)
                        await this.doGetSubscriptionData();
                    })
                    .height('100%')

            }
            .justifyContent(FlexAlign.Center)
            .width('100%')
            .height(40)

            Column({ space: 8 }) {
                Text('Subscription Content')
                List({ space: 8 }) {
                    ForEach(this.subscriptionContent, (item: string) => {
                        ListItem() {
                            Text(item)
                        }
                        .border({ color: Color.Red, width: 1 })
                        .backgroundColor($r('sys.color.gray_03'))
                    })
                }
                .width('100%')
                .height(250)
                .backgroundColor($r('sys.color.gray_02'))
            }
            .layoutWeight(1)

            Button('Start Decoding')
                .margin(16)
                .onClick(() => {
                    this.decoded = [];
                    this.decode();
                })

            Column({ space: 8 }) {
                Text('Decoded Content')
                List({ space: 8 }) {
                    ForEach(this.decoded, (item: string) => {
                        ListItem() {
                            Text(item)
                        }
                        .border({ color: Color.Green, width: 1 })
                        .backgroundColor($r('sys.color.gray_03'))
                    })
                }
                .width('100%')
                .height(250)
                .backgroundColor($r('sys.color.gray_02'))
            }
            .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding(8)
    }
}
