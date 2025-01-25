// SPDX-License-Identifier: GPL-3.0-or-later
import hilog from '@ohos.hilog'

export default class Logging {
    static Debug(component: string, message: string) {
        hilog.debug(0xACBD, component, message)
    }

    static Info(component: string, message: string) {
        hilog.info(0xACBD, component, message)
    }

    static Warn(component: string, message: string) {
        hilog.warn(0xACBD, component, message)
    }

    static Error(component: string, message: string) {
        hilog.error(0xACBD, component, message)
    }
};
