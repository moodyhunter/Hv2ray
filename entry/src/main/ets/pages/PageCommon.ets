import { Stat } from "../utils/Common";
import { CommonEventUtils } from "../utils/CommonEventUtils";

export function prettyPrintBytes(bytes: number): string {
    if (bytes === 0) {
        return "0 B";
    }

    const k = 1024;
    const dm = 2;
    const units = ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB"];
    for (let i = 0; i < units.length; i++) {
        if (bytes < k) {
            return bytes.toFixed(dm) + " " + units[i];
        }
        bytes /= k;
    }

    return bytes.toFixed(dm) + " " + units[units.length - 1];
}

@ObservedV2
export class GuiStatObject {
    @Trace rxRate: number = 0;
    @Trace txRate: number = 0;
    @Trace rxTotal: number = 0;
    @Trace txTotal: number = 0;

    constructor() {
        CommonEventUtils.subscribeStatsEvent((stat: Stat) => {
            this.rxRate = stat.rx;
            this.txRate = stat.tx;
            this.rxTotal += stat.rx;
            this.txTotal += stat.tx;
        });
    }

    public get rxRateString() {
        return prettyPrintBytes(this.rxRate) + '/s';
    }

    public get txRateString() {
        return prettyPrintBytes(this.txRate) + '/s';
    }
}

let statObject = new GuiStatObject();
export { statObject as GlobalStat };