import { KernelEvent, KernelEventType, Stat } from "../utils/Common";
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
    @Trace proxyUpRate: number = 0;
    @Trace proxyDownRate: number = 0;
    @Trace directUpRate: number = 0;
    @Trace directDownRate: number = 0;

    @Trace proxyUpTotal: number = 0;
    @Trace proxyDownTotal: number = 0;
    @Trace directUpTotal: number = 0;
    @Trace directDownTotal: number = 0;

    constructor() {
        CommonEventUtils.subscribeStatsEvent((stat: Stat) => {
            this.proxyUpRate = stat.proxyUp;
            this.proxyDownRate = stat.proxyDown;
            this.proxyUpTotal += stat.proxyUp;
            this.proxyDownTotal += stat.proxyDown;

            this.directUpRate = stat.directUp;
            this.directDownRate = stat.directDown;
            this.directUpTotal += stat.directUp;
            this.directDownTotal += stat.directDown;
        });
    }

    public get rxRateString() {
        return prettyPrintBytes(this.proxyDownRate) + '/s';
    }

    public get txRateString() {
        return prettyPrintBytes(this.proxyUpRate) + '/s';
    }
}

let statObject = new GuiStatObject();
export { statObject as GlobalStat };

@ObservedV2
export class GuiKernelStatusObject {
    @Trace status: KernelEventType = KernelEventType.Stopped;

    constructor() {
        CommonEventUtils.subscribeKernelEvent((event: KernelEvent) => {
            this.status = event.type;
        });
    }
}

let kernelStatusObject = new GuiKernelStatusObject();
export { kernelStatusObject as GlobalKernelStatus };

export function kernelStatusColor(status: KernelEventType): Color {
    switch (status) {
        case KernelEventType.Starting: return Color.Yellow;
        case KernelEventType.Started: return Color.Green;
        case KernelEventType.Crashed: return Color.Red;
        case KernelEventType.Stopped: return Color.Blue;
    }
}

export function kernelStatusLabel(status: KernelEventType): Resource {
    switch (status) {
        case KernelEventType.Starting: return $r('app.string.status_starting');
        case KernelEventType.Started: return $r('app.string.status_started');
        case KernelEventType.Crashed: return $r('app.string.status_crashed');
        case KernelEventType.Stopped: return $r('app.string.status_stopped');
    }
}