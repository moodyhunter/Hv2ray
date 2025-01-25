// SPDX-License-Identifier: GPL-3.0-or-later
import { AbilityConstant, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import Logging from '../utils/Logging';

const TAG = "Hv2ray-EntryAbility";

export default class EntryAbility extends UIAbility {
    async onCreate(_want: Want, launchParam: AbilityConstant.LaunchParam) {
        this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        Logging.Info(TAG, "onCreate");
    }

    onWindowStageCreate(windowStage: window.WindowStage): void {
        // Main window is created, set main page for this ability
        Logging.Info(TAG, "onWindowStageCreate");

        windowStage.loadContent('pages/Index', (err) => {
            if (err.code) {
                Logging.Error(TAG, `Failed to load the content, error: ${JSON.stringify(err)}`);
                return;
            }
            Logging.Info(TAG, "Succeeded in loading the content.");
        });
    }

    onWindowStageDestroy(): void {
        // Main window is destroyed, release UI related resources
        Logging.Info(TAG, "onWindowStageDestroy");
    }

    onForeground(): void {
        // Ability has brought to foreground
        Logging.Info(TAG, "onForeground");
    }

    onBackground(): void {
        // Ability has back to background
        Logging.Info(TAG, "onBackground");
    }
};
