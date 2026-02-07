
export enum KernelEventType {
    Starting = 0,
    Started = 1,
    Crashed = 2,
    Stopped = 3,
}

export interface KernelEvent {
    type: KernelEventType;
    message: string[];
}

export interface Stat {
    tx: number;
    rx: number;
}

export class Constants {
    static readonly KERNEL_EVENT_NAME = 'hv2ray.events.kernel';
    static readonly STATS_EVENT_NAME = 'hv2ray.events.stats'; // content is of type Stats
}
