import { buffer, util } from "@kit.ArkTS";

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
    directUp: number;
    directDown: number;
    proxyUp: number;
    proxyDown: number;
}

export class Constants {
    static readonly KERNEL_EVENT_NAME = 'hv2ray.events.kernel';
    static readonly STATS_EVENT_NAME = 'hv2ray.events.stats'; // content is of type Stats
}

export class Utils {
    public static base64Decode(input: string): string {
        let base64 = new util.Base64Helper();
        let decodeResult = base64.decodeSync(input);
        let decoder = new util.StringDecoder()
        return decoder.write(decodeResult);
    }

    public static isUnsignedDecimal(input: string): boolean {
        if (input.length === 0) {
            return false;
        }
        for (let i = 0; i < input.length; i++) {
            const char = input.charAt(i);
            if (char < '0' || char > '9') {
                return false;
            }
        }
        return true;
    }

}