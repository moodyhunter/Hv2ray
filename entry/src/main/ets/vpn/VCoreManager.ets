import native from 'libnative.so';
import { KernelEventType } from '../utils/Common';
import { CommonEventUtils } from '../utils/CommonEventUtils';

export namespace VCoreManager {
    export function StartVCore(socks5Port: number, config: string): boolean {
        try {
            native.startVCore(socks5Port, config);
        } catch (e) {
            let errMsg: string[] = [];
            for (let line of (e.message as string)
                .split('>')) {
                line = line.trim();
                errMsg.push(line);
            }
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, e.message);
            return false;
        }

        return true;
    }

    export function StopVCore() {
        native.stopVCore()
    }
}