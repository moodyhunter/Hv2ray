import native from 'libnative.so';
import { KernelEventType } from '../utils/Common';
import { CommonEventUtils } from '../utils/CommonEventUtils';

export namespace VCoreManager {
    export interface StartVCoreParams {
        config: string;
        statsPort: number;
        directTag: string;
        proxyTag: string;
    }
    export function StartVCore(params: StartVCoreParams): boolean {
        try {
            native.startVCore(params.config, params.statsPort, params.directTag, params.proxyTag);
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