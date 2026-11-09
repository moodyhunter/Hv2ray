// SPDX-License-Identifier: GPL-3.0-or-later
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import Logger from '../utils/Logging';
import native from 'libnative.so';
import { KernelEventType, Stat } from '../utils/Common';
import { CommonEventUtils } from '../utils/CommonEventUtils';
import { BUNDLE_NAME } from 'BuildProfile';
import { VCoreManager } from './VCoreManager';
import { fileIo } from '@kit.CoreFileKit';

const TAG = "Hv2ray-VpnAbility";
const TUN_IP = "198.18.0.1";

export class VpnAbility extends VpnExtensionAbility {
    private vpnConnection: vpnExtension.VpnConnection = null!;
    private kernelCrashed: boolean = false;

    private async doCreateVpn(want: Want): Promise<void> {
        this.kernelCrashed = false;

        try {
            let config: vpnExtension.VpnConfig = {
                addresses: [{ address: { address: TUN_IP, family: 1 }, prefixLength: 24 }],
                dnsAddresses: ['1.1.1.1'],
                blockedApplications: [BUNDLE_NAME]
            };
            const tunFd = await this.vpnConnection.create(config);
            Logger.Info(TAG, `Starting VPN on fd ${tunFd}`);

            this.vpnConnection.protectProcessNet();

            const params: VCoreManager.StartVCoreParams = JSON.parse(want.parameters!['params'] as string);
            params.config = params.config.replace('<<FDXXX>>', 'fd:' + tunFd.toString());

            if (VCoreManager.StartVCore(params)) {
                Logger.Warn(TAG, `StartVCore succeeded`);
                native.onStatisticsEvent((stats: Stat) => {
                    CommonEventUtils.publishStatsEvent(stats);
                });
                CommonEventUtils.publishKernelErrorEvent(KernelEventType.Started);
            } else {
                CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed);
                return Promise.reject();
            }
        } catch (e) {
            Logger.Error(TAG, `Failed to start VPN: ${e.message}`);
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, e.message);
            return Promise.reject();
        }
    }

    onCreate(want: Want): void {
        Logger.Info(TAG, `VpnAbility onCreate`);
        // list files in configuration dir
        const configFile = this.context.tempDir + '/test.conf';
        try {
            Logger.Error(TAG, `accessing file: ${JSON.stringify(configFile)}`);
            fileIo.openSync(configFile, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE);
        } catch (e) {
            Logger.Error(TAG, `failed to access files: ${JSON.stringify(e)}, ${configFile}`);
        }
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
