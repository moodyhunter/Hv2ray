// SPDX-License-Identifier: GPL-3.0-or-later
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import Logger from '../utils/Logging';
import native from 'libnative.so';
import { KernelEventType, Stat } from '../utils/Common';
import { CommonEventUtils } from '../utils/CommonEventUtils';
import { BUNDLE_NAME } from 'BuildProfile';
import { VCoreManager } from './VCoreManager';

const TAG = "Hv2ray-VpnAbility";
const TUN_IP = "198.18.0.1";

export class VpnAbility extends VpnExtensionAbility {
    private vpnConnection: vpnExtension.VpnConnection = null!;
    private kernelCrashed: boolean = false;

    /**
     * 启动参数只在主能力调用 startVpnExtensionAbility 时才会带上：系统按 wantAgent
     * 重新拉起 VpnAbility 时 want 里什么都没有。没有配置就不要把空串交给内核，
     * 它只会回一句看不懂的 "infra/conf/v5cfg: unable to load json > EOF"。
     */
    private parseStartParams(want: Want): VCoreManager.StartVCoreParams | undefined {
        const raw = (want.parameters?.['params'] ?? '') as string;
        if (raw.length === 0) {
            Logger.Error(TAG, `VpnAbility started without start parameters`);
            return undefined;
        }

        try {
            const params: VCoreManager.StartVCoreParams = JSON.parse(raw);
            if (!params.config || params.config.length === 0) {
                Logger.Error(TAG, `VpnAbility started with an empty configuration`);
                return undefined;
            }
            return params;
        } catch (e) {
            Logger.Error(TAG, `failed to parse start parameters: ${e.message}`);
            return undefined;
        }
    }

    private async doCreateVpn(want: Want): Promise<void> {
        this.kernelCrashed = false;

        const params = this.parseStartParams(want);
        if (!params) {
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, ['no configuration to start']);
            return Promise.reject();
        }

        try {
            let config: vpnExtension.VpnConfig = {
                addresses: [{ address: { address: TUN_IP, family: 1 }, prefixLength: 24 }],
                dnsAddresses: ['1.1.1.1'],
                blockedApplications: [BUNDLE_NAME]
            };
            const tunFd = await this.vpnConnection.create(config);
            Logger.Info(TAG, `Starting VPN on fd ${tunFd}`);

            this.vpnConnection.protectProcessNet();

            params.config = params.config.replace('<<FDXXX>>', 'fd:' + tunFd.toString());

            if (VCoreManager.StartVCore(params)) {
                Logger.Warn(TAG, `StartVCore succeeded`);
                native.onStatisticsEvent((stats: Stat) => {
                    CommonEventUtils.publishStatsEvent(stats);
                });
                CommonEventUtils.publishKernelErrorEvent(KernelEventType.Started);
            } else {
                // 内核自己的错误内容由 StartVCore 作为 Crashed 事件发出去了。这里不能再补
                // 一发不带 message 的事件：Home 页会为每个 Crashed 弹一个对话框，那条空的
                // 就是"弹窗没有内容"。
                return Promise.reject();
            }
        } catch (e) {
            Logger.Error(TAG, `Failed to start VPN: ${e.message}`);
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, [`Failed to start VPN: ${e.message}`]);
            return Promise.reject();
        }
    }

    onCreate(want: Want): void {
        Logger.Info(TAG, `VpnAbility onCreate`);
        CommonEventUtils.publishKernelErrorEvent(KernelEventType.Starting);
        this.vpnConnection = vpnExtension.createVpnConnection(this.context);
        this.doCreateVpn(want)
            .catch(() => {
                this.kernelCrashed = true;
                this.cleanupVpn();
            });
    }

    private async cleanupVpn() {
        VCoreManager.StopVCore();
        const want: Want = {
            bundleName: BUNDLE_NAME,
            abilityName: 'VpnAbility',
        };
        await this.vpnConnection.destroy()
            .catch(() => {
                Logger.Error(TAG, `failed to destroy vpnConnection`);
            });
        await vpnExtension.stopVpnExtensionAbility(want)
            .catch(() => {
                Logger.Error(TAG, `failed to stop VpnAbility`);
            });
    }

    async onDestroy() {
        if (!this.kernelCrashed) {
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Stopped);
        }
        VCoreManager.StopVCore();
        try {
            await this.vpnConnection.destroy()
        } catch (error) {
            Logger.Error(TAG, `failed to destroy vpnConnection: ${JSON.stringify(error)}`);
        }
        Logger.Info(TAG, `Stopped VPN`)
    }
}
