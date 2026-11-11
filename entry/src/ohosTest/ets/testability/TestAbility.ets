import UIAbility from '@ohos.app.ability.UIAbility';
import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import AbilityConstant from '@ohos.app.ability.AbilityConstant';
import Want from '@ohos.app.ability.Want';
import hilog from '@ohos.hilog';
import window from '@ohos.window';
import { Hypium } from '@ohos/hypium';
import testsuite from '../test/List.test';

export default class TestAbility extends UIAbility {
    onCreate(want: Want, launchParam: AbilityConstant.LaunchParam) {
        hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onCreate');
        hilog.info(0x0000, 'testTag', '%{public}s', `want: ${JSON.stringify(want) ?? ''}`);
        hilog.info(0x0000, 'testTag', '%{public}s', `launchParam: ${JSON.stringify(launchParam) ?? ''}`);
        const abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();
        const abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
        Hypium.hypiumTest(abilityDelegator, abilityDelegatorArguments, testsuite);
    }

    onDestroy(): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onDestroy');
    }

    onWindowStageCreate(windowStage: window.WindowStage): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onWindowStageCreate');
        windowStage.loadContent('testability/pages/Index')
            .catch((e: BusinessError): void => {
                hilog.error(0x0000, 'testTag', 'Failed to load the content: %{public}s', JSON.stringify(e) ?? '');
            });
    }

    onWindowStageDestroy(): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onWindowStageDestroy');
    }

    onForeground(): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onForeground');
    }

    onBackground(): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'TestAbility onBackground');
    }
}
