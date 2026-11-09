import { CommonPicker } from './CommonPicker';
import { DrawerController, Drawer } from './Drawer';
import { FilterOption, ResultItem, LayoutType } from '../types/Index';

@ComponentV2
export struct FilterList {
    @Require @Param filterOptions: FilterOption[];
    @Param layoutStyle: LayoutType = LayoutType.DEFAULT;
    @BuilderParam listBuilderParam: () => void = this.lisBuilder;
    @Local isDrawOpen: boolean = false;
    @Local curIndex: number = -1;
    @Local selectResult: ResultItem[] = [];
    controller: DrawerController = new DrawerController();
    @Event onChange: (res: ResultItem[]) => void = () => {

    };

    @Builder
    lisBuilder() {

    }

    build() {
        Column() {
            Scroll() {
                Row({ space: 16 }) {
                    ForEach(this.filterOptions, (item: FilterOption, index) => {
                        Row({ space: 2 }) {
                            Text(item.selectArr[item.selectIndex] || item.name)
                                .fontSize($r('sys.float.Body_M'))
                                .fontWeight(FontWeight.Regular)
                                .fontColor(this.curIndex === index && this.isDrawOpen ? $r('sys.color.font_primary') :
                                    $r('sys.color.font_secondary'));
                            Image(this.curIndex === index && this.isDrawOpen ? $r('app.media.ic_arrow_on') :
                                $r('app.media.ic_arrow_off'))
                                .width(12)
                                .height(12);
                        }
                        .onClick(() => {
                            if (this.isDrawOpen && this.curIndex === index) {
                                this.controller.close();
                                this.curIndex = -1;
                            } else {
                                this.curIndex = index;
                                this.controller.open();
                            }
                        });
                    }, (item: FilterOption) => item.name + item.selectIndex);
                }
                .height(39)
                .justifyContent(this.layoutStyle === LayoutType.DEFAULT ? FlexAlign.SpaceBetween : FlexAlign.Start)
            }
            .scrollable(ScrollDirection.Horizontal)
            .scrollBar(BarState.Off)
            .width('100%')
            .padding({ top: 8 }) 
            .padding({ left: 16, right: 16 })

            if (this.layoutStyle === LayoutType.SPLIT) {
                Divider()
                    .width('100%')
                    .color($r('sys.color.comp_divider'));
            }

            Drawer({
                controller: this.controller,
                onDrawerChange: (res) => {
                    this.isDrawOpen = res;
                },
            }) {
                CommonPicker({
                    curIndex: this.filterOptions[this.curIndex].selectIndex,
                    contentArr: this.filterOptions[this.curIndex].selectArr,
                    onItemClick: (index) => {
                        this.filterOptions[this.curIndex].selectIndex = index;
                        this.selectResult = this.filterOptions.map((item) => {
                            const obj: ResultItem = {
                                filterName: item.name,
                                selectIndex: item.selectIndex,
                            };
                            return obj;
                        });
                        this.onChange(this.selectResult);
                        this.controller.close();
                    },
                })
            }

            this.listBuilderParam()
        }
        .width('100%')
        .layoutWeight(1);
    }
}