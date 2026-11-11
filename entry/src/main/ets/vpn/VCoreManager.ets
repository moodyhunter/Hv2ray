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
            // 内核的错误串按 '>' 分段，拆开是为了在弹窗里一段一行。发出去的一定要是
            // string[]：Home 页取的是 message.join('\n')，直接把 e.message 传过去，
            // 那段代码连 join 都调不出来，弹窗就没有内容。
            const errMsg: string[] = [];
            for (let line of (e.message as string)
                .split('>')) {
                line = line.trim();
                if (line.length > 0) {
                    errMsg.push(line);
                }
            }
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, errMsg);
            return false;
        }

        return true;
    }

    export function StopVCore() {
        native.stopVCore()
    }
}