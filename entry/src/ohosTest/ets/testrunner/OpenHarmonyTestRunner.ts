import abilityDelegatorRegistry from '@ohos.app.ability.abilityDelegatorRegistry';
import hilog from '@ohos.hilog';
import TestRunner from '@ohos.application.testRunner';

let abilityDelegator: abilityDelegatorRegistry.AbilityDelegator;
let abilityDelegatorArguments: abilityDelegatorRegistry.AbilityDelegatorArgs;
const TEST_ABILITY = 'TestAbility';

async function onAbilityCreateCallback(): Promise<void> {
    hilog.info(0x0000, 'testTag', '%{public}s', 'onAbilityCreateCallback');
}

async function addAbilityMonitorCallback(err: Error): Promise<void> {
    hilog.info(0x0000, 'testTag', 'addAbilityMonitorCallback : %{public}s', JSON.stringify(err) ?? '');
}

export default class OpenHarmonyTestRunner implements TestRunner {
    constructor() {
    }

    onPrepare(): void {
        hilog.info(0x0000, 'testTag', '%{public}s', 'OpenHarmonyTestRunner OnPrepare');
    }

    async onRun(): Promise<void> {
        hilog.info(0x0000, 'testTag', '%{public}s', 'OpenHarmonyTestRunner onRun run');
        abilityDelegatorArguments = abilityDelegatorRegistry.getArguments();
        abilityDelegator = abilityDelegatorRegistry.getAbilityDelegator();

        const parameters = abilityDelegatorArguments.parameters;
        const moduleName = parameters['-m'];
        const isDebug = parameters['-D'] === 'true';
        const monitor: abilityDelegatorRegistry.AbilityMonitor = {
            abilityName: TEST_ABILITY,
            onAbilityCreate: onAbilityCreateCallback,
            moduleName: moduleName
        };
        abilityDelegator.addAbilityMonitor(monitor, addAbilityMonitorCallback);

        // 走 shell 而不是 startAbility：屏幕未解锁时能拿到明确的失败并结束测试。
        let command = `aa start -b ${abilityDelegatorArguments.bundleName} -a ${TEST_ABILITY} -m ${moduleName}`;
        if (isDebug) {
            command += ' -D';
        }
        await abilityDelegator.executeShellCommand(command)
            .then((result: abilityDelegatorRegistry.ShellCmdResult): void => {
                const output = result.stdResult;
                if (output.includes('error: unlock screen failed in developer mode') || output.includes('10106102')) {
                    hilog.info(0x0000, 'testTag', '%{public}s', `startAbility failed: ${output}`);
                    abilityDelegator.finishTest('', -3, (): void => {
                    });
                }
            })
            .catch((err: string): void => {
                hilog.info(0x0000, 'testTag', 'startAbility error: %{public}s', err);
            });
        hilog.info(0x0000, 'testTag', '%{public}s', 'OpenHarmonyTestRunner onRun end');
    }
}
