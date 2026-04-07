// SPDX-License-Identifier: GPL-3.0-or-later
import hilog from '@ohos.hilog'

const GLOBAL_TAG = 'Hv2ray';

export default class Logger {
    static Debug(component: string, message: string) {
        hilog.debug(0xABCD, GLOBAL_TAG, `[${component}] ${message}`)
    }

    static Info(component: string, message: string) {
        hilog.info(0xABCD, GLOBAL_TAG, `[${component}] ${message}`)
    }

    static Warn(component: string, message: string) {
        hilog.warn(0xABCD, GLOBAL_TAG, `[${component}] ${message}`)
    }

    static Error(component: string, message: string) {
        hilog.error(0xABCD, GLOBAL_TAG, `[${component}] ${message}`)
    }
}
