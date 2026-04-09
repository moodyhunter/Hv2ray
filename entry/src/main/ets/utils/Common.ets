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
    tx: number;
    rx: number;
}

export class Constants {
    static readonly KERNEL_EVENT_NAME = 'hv2ray.events.kernel';
    static readonly STATS_EVENT_NAME = 'hv2ray.events.stats'; // content is of type Stats
}

export class Utils {
    public static base64Decode(input: string): string {
        // let base64 = new util.Base64Helper();
        // let decodeResult = base64.decodeSync(input);
        // let decoder = new util.StringDecoder()
        // return decoder.write(decodeResult);

        let base64: util.Base64Helper = new util.Base64Helper();
        const stringData: Uint8Array = base64.decodeSync(input);
        // 先将 Uint8Array 转换为 Buffer，然后使用 toString
        const buf: buffer.Buffer = buffer.from(stringData);
        const plainString: string = buf.toString('utf8'); // 使用'utf8'编码
        return plainString
    }

}