// SPDX-License-Identifier: GPL-3.0-or-later
import { AbilityConstant, ConfigurationConstant, UIAbility, Want, wantAgent } from '@kit.AbilityKit';
import { AppStorageV2, window } from '@kit.ArkUI';
import { BUNDLE_NAME } from 'BuildProfile';
import Logger from '../utils/Logging';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import { ConfigManager, ConfigManagerImpl } from '../core/config/ConfigManager';

const TAG = "Hv2ray-EntryAbility";

export default class EntryAbility extends UIAbility {
    async onCreate(_want: Want, launchParam: AbilityConstant.LaunchParam) {
        this.context.getApplicationContext()
            .setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
        Logger.Info(TAG, "onCreate");
        await ConfigManager.loadConfigurations();
        await ConfigManager.saveConfigurations();
        await this.startBackgroundRunning();
    }

    async onWindowStageCreate(windowStage: window.WindowStage): Promise<void> {
        Logger.Info(TAG, "onWindowStageCreate");
        await windowStage.loadContent('pages/Index')
            .catch((e: BusinessError) => {
                Logger.Error(TAG, `Failed to load the content, error: ${JSON.stringify(e)}`);
            });

        try {
            let mainWindow = await windowStage.getMainWindow();
            mainWindow.setWindowDecorVisible(false);
            mainWindow.setWindowDecorHeight(60);
        } catch (error) {
            Logger.Error(TAG, `failed to set window properties: ${JSON.stringify(error)}`)
        }
    }

    onWindowStageDestroy(): void {
        Logger.Info(TAG, "onWindowStageDestroy");
    }

    onForeground(): void {
        // Ability has brought to foreground
        Logger.Info(TAG, "onForeground");
    }

    onBackground(): void {
        // Ability has back to background
        Logger.Info(TAG, "onBackground");
    }

    async onPrepareToTerminateAsync(): Promise<boolean> {
        return true;
    }

    private async startBackgroundRunning() {
        Logger.Info(TAG, `startBackgroundRunning`);
        try {
            const WANT_AGENT_INFO: wantAgent.WantAgentInfo = {
                wants: [{ bundleName: BUNDLE_NAME, abilityName: "EntryAbility" }],
                actionType: wantAgent.OperationType.START_ABILITY,
                requestCode: 0,
                wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
            };
            let wantAgentObj = await wantAgent.getWantAgent(WANT_AGENT_INFO);
            let req = new backgroundTaskManager.ContinuousTaskRequest();
            req.backgroundTaskModes = [backgroundTaskManager.BackgroundTaskMode.MODE_TASK_KEEPING];
            req.backgroundTaskSubmodes = [backgroundTaskManager.BackgroundTaskSubmode.SUBMODE_NORMAL_NOTIFICATION];
            req.wantAgent = wantAgentObj;

            let res = await backgroundTaskManager.startBackgroundRunning(this.context, req);
            Logger.Info(TAG, `startBackgroundRunning: succeeded: ${JSON.stringify(res)}`);
        } catch (error) {
            let e = error as BusinessError;
            Logger.Error(TAG, `startBackgroundRunning: failed. code is ${e.code} message is ${e.message}`);
        }
    }
}

