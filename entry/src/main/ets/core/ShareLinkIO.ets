@ComponentV2
export struct ABC {
    @Local time: string = new Date().toString();

    @Builder
    content() {
        Text('abcTest: ' + this.time)
    }

    build() {
        Column() {
            this.content()
            QRCode('abc')
        }
    }
}

@Builder
export function shareLinkIoBuilder()
{
    ABC()
}