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

    private async decode(): Promise<void> {
        for (const line of this.subscriptionContent) {
            const item = this.decodeOne(line);
            if (item) {
                this.decoded.push(JSON.stringify(item));

                let configRoot: ConfigRoot = {
                    inbounds: [],
                    outbounds: [
                        item.outbound
                    ],
                    router: {
                        domainStrategy: 'IpIfNonMatch',
                        rule: []
                    }
                };
                // 逐条 await：并发的 addConnectionToGroup 会对同一个 groups.json 交错写入。
                await ConfigManager.addConnectionToGroup(item.name, 'subscription', configRoot)
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
            Text($r('app.string.cfg_use_proxy'))
        }
    }

    build() {
        Column({ space: 16 }) {
            // 以本容器宽度为参照划分断点：窄屏输入框与操作分行，宽屏一行排完。
            // columns 必须显式写 12，否则 API 20 起默认按 {xs:2,sm:4,md:8,lg:12} 夹取 span。
            GridRow({
                gutter: { x: 8, y: 8 },
                columns: 12,
                breakpoints: { reference: BreakpointsReference.ComponentSize }
            }) {
                GridCol({ span: { xs: 12, sm: 12, md: 6, lg: 8 } }) {
                    TextInput({ placeholder: $r('app.string.cfg_sub_link_hint'), text: this.subscriptionLink!! })
                        .width('100%')
                }

                GridCol({ span: { xs: 6, sm: 6, md: 3, lg: 2 } }) {
                    this.useProxyCheckbox();
                }

                GridCol({ span: { xs: 6, sm: 6, md: 3, lg: 2 } }) {
                    Button($r('app.string.cfg_btn_get'))
                        .width('100%')
                        .onClick(async () => {
                            Logger.Warn(TAG, `GET using proxy: ${this.useProxy}`)
                            await this.doGetSubscriptionData();
                        })
                }
            }
            .alignItems(ItemAlign.Center)
            .width('100%')

            Column({ space: 8 }) {
                Text($r('app.string.cfg_sub_content'))
                List({ space: 8 }) {
                    ForEach(this.subscriptionContent, (item: string) => {
                        ListItem() {
                            Text(item)
                                .maxLines(2)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                .wordBreak(WordBreak.BREAK_ALL)
                        }
                        .border({ color: Color.Red, width: 1 })
                        .backgroundColor($r('sys.color.gray_03'))
                    })
                }
                .width('100%')
                .layoutWeight(1)
                .backgroundColor($r('sys.color.gray_02'))
            }
            .layoutWeight(1)
            .width('100%')

            Button($r('app.string.cfg_btn_decode'))
                .margin(16)
                .onClick(async () => {
                    this.decoded = [];
                    await this.decode();
                })

            Column({ space: 8 }) {
                Text($r('app.string.cfg_decoded_content'))
                List({ space: 8 }) {
                    ForEach(this.decoded, (item: string) => {
                        ListItem() {
                            Text(item)
                                .maxLines(2)
                                .textOverflow({ overflow: TextOverflow.Ellipsis })
                                .wordBreak(WordBreak.BREAK_ALL)
                        }
                        .border({ color: Color.Green, width: 1 })
                        .backgroundColor($r('sys.color.gray_03'))
                    })
                }
                .width('100%')
                .layoutWeight(1)
                .backgroundColor($r('sys.color.gray_02'))
            }
            .layoutWeight(1)
            .width('100%')
        }
        .width('100%')
        .height('100%')
        .padding(8)
    }
}
