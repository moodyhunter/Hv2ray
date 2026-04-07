import { http } from "@kit.NetworkKit";
import Logger from "../utils/Logging";
import { util } from "@kit.ArkTS";
import { ABC, shareLinkIoBuilder } from "../core/ShareLinkIO";

const TAG = 'Pages/Configuration';

@Builder
function noopBuilder() {
    Text('NOOP')
}

@ComponentV2
export struct Configurations {
    private subscriptionLink: string = '';
    @Local private subscriptionContent: string = '';
    @Local private subscriptionContent2: string = '';
    @Local private abc: ABC = new ABC();

    builderVar: WrappedBuilder<[]> = wrapBuilder(noopBuilder);

    aboutToAppear(): void {
        this.builderVar = wrapBuilder(shareLinkIoBuilder);
    }

    build() {
        Column() {
            this.builderVar.builder()
            TextInput({ placeholder: 'subscription link' })
                .onChange((content: string) => {
                    this.subscriptionLink = content;
                })
            Button('GET')
                .onClick(async () => {
                    try {
                        const req = http.createHttp();
                        let options: http.HttpRequestOptions = {
                            usingProxy: {
                                host: '127.0.0.1',
                                port: 12345,
                                exclusionList: []
                            }
                        };
                        let response = await req.request(this.subscriptionLink, options);
                        // Logger.Info(TAG, JSON.stringify(response.result));
                        this.subscriptionContent = response.result as string;

                        let base64 = new util.Base64Helper();

                        let decodeResult = base64.decodeSync(this.subscriptionContent); //base64转Uint8Array

                        console.info('Decode result: ', decodeResult);

                        let decoder = new util.StringDecoder()
                        this.subscriptionContent2 = decoder.write(decodeResult);
                    } catch (e) {
                        Logger.Error(TAG, `error: ${JSON.stringify(e)}`);
                    }
                })

            Text(this.subscriptionContent)
                .maxLines(10)

            TextArea({ text: this.subscriptionContent2 })
        }
    }
}
