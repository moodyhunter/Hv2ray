import { HomeGroupOption } from './HomeCommon';

const MOVE_RADIO_GROUP = 'homeMoveConnectionGroup';

/** 编辑半模态里的表单草稿；连接不存在时为空，打开前由 Home 填好 */
@ObservedV2
export class HomeEditDraft {
    @Trace connId: string = '';
    @Trace connName: string = '';
    @Trace hostText: string = '';
    @Trace portText: string = '';
    @Trace protocolText: string = '';
    @Trace transportText: string = '';
    @Trace groupId: string = '';
    @Trace groupOptions: HomeGroupOption[] = [];
}

@ComponentV2
struct HomeEditField {
    @Require @Param fieldLabel: Resource;
    @Require @Param fieldValue: string;
    @Param numericInput: boolean = false;
    @Event onFieldValue: (value: string) => void = (value: string): void => {
    };

    build() {
        Column({ space: 4 }) {
            Text(this.fieldLabel)
                .fontSize(13)
                .fontColor($r('sys.color.font_secondary'))
            TextInput({ text: this.fieldValue })
                .type(this.numericInput ? InputType.Number : InputType.Normal)
                .width('100%')
                .onChange((value: string): void => {
                    this.onFieldValue(value);
                })
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
    }
}

/**
 * 半模态里的编辑表单。这里只管表单：校验与写盘都在 Home（它持有 ConfigManager 的变更入口），
 * 所以点保存只是把事件抛回去。
 */
@ComponentV2
export struct HomeEditSheetForm {
    @Require @Param draft: HomeEditDraft;
    @Event onSave: () => void = (): void => {
    };
    @Event onCancel: () => void = (): void => {
    };

    @Builder
    groupOptions() {
        Row({ space: 16 }) {
            ForEach(this.draft.groupOptions, (option: HomeGroupOption) => {
                Row({ space: 4 }) {
                    Radio({
                        value: option.id,
                        group: MOVE_RADIO_GROUP
                    })
                        .checked(this.draft.groupId === option.id)
                        .onChange((isChecked: boolean): void => {
                            if (isChecked) {
                                this.draft.groupId = option.id;
                            }
                        })

                    Text(option.name)
                        .fontSize(14)
                }
            }, (option: HomeGroupOption): string => option.id)
        }
        .width('100%')
    }

    build() {
        Column({ space: 12 }) {
            Scroll() {
                Column({ space: 12 }) {
                    HomeEditField({
                        fieldLabel: $r('app.string.field_connection_name'),
                        fieldValue: this.draft.connName,
                        onFieldValue: (value: string): void => {
                            this.draft.connName = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_host'),
                        fieldValue: this.draft.hostText,
                        onFieldValue: (value: string): void => {
                            this.draft.hostText = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_port'),
                        fieldValue: this.draft.portText,
                        numericInput: true,
                        onFieldValue: (value: string): void => {
                            this.draft.portText = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_protocol'),
                        fieldValue: this.draft.protocolText,
                        onFieldValue: (value: string): void => {
                            this.draft.protocolText = value;
                        },
                    })

                    HomeEditField({
                        fieldLabel: $r('app.string.field_transport'),
                        fieldValue: this.draft.transportText,
                        onFieldValue: (value: string): void => {
                            this.draft.transportText = value;
                        },
                    })

                    Text($r('app.string.field_group'))
                        .fontSize(13)
                        .fontColor($r('sys.color.font_secondary'))

                    this.groupOptions();
                }
                .width('100%')
            }
            .layoutWeight(1)
            .width('100%')

            Row({ space: 8 }) {
                Button($r('app.string.btn_cancel'))
                    .layoutWeight(1)
                    .onClick((): void => {
                        this.onCancel();
                    })

                Button($r('app.string.btn_save'))
                    .layoutWeight(1)
                    .onClick((): void => {
                        this.onSave();
                    })
            }
            .width('100%')
        }
        .padding(16)
        .width('100%')
        .height('100%')
    }
}
