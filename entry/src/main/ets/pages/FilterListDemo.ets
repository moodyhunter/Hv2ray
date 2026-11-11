import Logger from '../utils/Logging';
import { FilterList, FilterOption, LayoutType, ResultItem } from 'module_filter_list';

const TAG = 'Hv2ray-FilterListDemo';

/**
 * Vendored module_filter_list showcase. It is demo content, not part of the
 * configuration list, so it lives on the Settings page behind DEBUG.
 */
@ComponentV2
export struct FilterListDemo {
    private types: string[] = [];
    private styles: string[] = [];
    @Local private typeIndex: number = 0;
    @Local private styleIndex: number = 0;
    @Local private listArr: string[] = [];
    @Local private filterOptions: FilterOption[] = [];

    private resText(name: Resource): string {
        try {
            return this.getUIContext()
                .getHostContext()!
                .resourceManager
                .getStringSync(name.id);
        } catch (error) {
            Logger.Error(TAG, `failed to load resource ${name.id}: ${JSON.stringify(error)}`);
            return '';
        }
    }

    aboutToAppear(): void {
        this.types = [
            this.resText($r('app.string.demo_room_1bed')),
            this.resText($r('app.string.demo_room_2bed')),
            this.resText($r('app.string.demo_room_3bed')),
            this.resText($r('app.string.demo_room_4bed')),
        ];
        this.styles = [
            this.resText($r('app.string.demo_style_wood')),
            this.resText($r('app.string.demo_style_minimal')),
            this.resText($r('app.string.demo_style_new_chinese')),
            this.resText($r('app.string.demo_style_cream')),
            this.resText($r('app.string.demo_style_wood')),
            this.resText($r('app.string.demo_style_minimal')),
            this.resText($r('app.string.demo_style_new_chinese')),
        ];
        this.filterOptions = [
            new FilterOption(this.resText($r('app.string.demo_filter_room_type')), this.typeIndex, this.types),
            new FilterOption(this.resText($r('app.string.demo_filter_style')), this.styleIndex, this.styles),
        ];
    }

    private onFilterListChange(res: ResultItem[]) {
        while (this.listArr.length > 0) {
            this.listArr.pop();
        }
        Logger.Info(TAG, `filter result: ${JSON.stringify(res)}`);
        for (const r of res) {
            this.listArr.push(`${r.filterName} - ${r.selectIndex}`);
        }
    }

    build() {
        Column() {
            FilterList(
                {
                    filterOptions: this.filterOptions,
                    layoutStyle: LayoutType.SPLIT,
                    onChange: (res: ResultItem[]) => {
                        this.onFilterListChange(res);
                    },
                },
            ) {
                List({ space: 12 }) {
                    ForEach(this.listArr, (item: string, _index: number) => {
                        ListItem() {
                            Column({ space: 12 }) {
                                Image($r('app.media.app_icon'))
                                    .width('100%')
                                    .height(140)
                                    .borderRadius(16)
                                    .draggable(false)

                                Text(item)
                            }
                        }
                    }, (item: string, index: number): string => `${index}_${item}`)
                }
                .width('100%')
                .height('100%')
                .padding({ top: 12, right: 16, left: 16 })
                .layoutWeight(1)
            }
        }
        .width('100%')
        .height(320)
    }
}
