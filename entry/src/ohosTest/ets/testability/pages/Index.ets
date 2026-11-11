@Entry
@Component
struct Index {
    @State message: string = 'Hv2ray backup tests are running';

    build() {
        Row() {
            Column() {
                Text(this.message)
                    .fontSize(24)
                    .fontWeight(FontWeight.Bold)
            }
            .width('100%')
        }
        .height('100%')
    }
}
