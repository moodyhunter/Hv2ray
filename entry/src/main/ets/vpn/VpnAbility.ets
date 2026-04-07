// SPDX-License-Identifier: GPL-3.0-or-later
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import Logger from '../utils/Logging';
import native from 'libnative.so';
import { KernelEventType, Stat } from '../utils/Common';
import { CommonEventUtils } from '../utils/CommonEventUtils';
import { BUNDLE_NAME } from 'BuildProfile';

const TAG = "Hv2ray-VpnAbility";
const TUN_IP = "198.18.0.1";

interface V2RayVpnParameters {
    config: string;
    socks5Port: number;
    dnsAddresses: string[];
    whitelist: string[];
    blacklist: string[];
}

export class VpnAbility extends VpnExtensionAbility {
    vpnConnection: vpnExtension.VpnConnection | null = null;
    socks5Port: number = 51081;
    kernelCrashed: boolean = false;

    async onCreate(want: Want) {
        Logger.Info(TAG, `VpnAbility onCreate`);
        CommonEventUtils.publishKernelErrorEvent(KernelEventType.Starting);
        if (this.vpnConnection == null) {
            this.vpnConnection = vpnExtension.createVpnConnection(this.context);
        }

        this.socks5Port = (want.parameters?.socks5Port as number | undefined) ?? 51081;

        let config: vpnExtension.VpnConfig = {
            addresses: [{ address: { address: TUN_IP, family: 1 }, prefixLength: 24 }],
            dnsAddresses: ['8.8.8.8', '8.8.4.4', '1.1.1.1'],
            blockedApplications: [BUNDLE_NAME]
        };
        let tunFd: number;
        try {
            tunFd = await this.vpnConnection.create(config);
        } catch (error) {
            Logger.Error(TAG, `failed to create new VpnConnection: ${JSON.stringify(error)}`);
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, [JSON.stringify(error)]);
            this.kernelCrashed = true;
            await this.vpnConnection.destroy();
            return;
        }
        if (tunFd < 0) {
            Logger.Error(TAG, `Failed to create VPN: ${tunFd}`);
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, [`Create VPN failed, ${tunFd}`]);
            this.kernelCrashed = true;
            return false;
        }

        Logger.Info(TAG, `Starting VPN on fd ${tunFd}`);

        try {
            native.startTun(tunFd, this.socks5Port);
            native.onStatisticsEvent(1, (stats: Stat) => {
                CommonEventUtils.publishStatsEvent(stats);
            });
        } catch (e) {
            Logger.Error(TAG, `Failed to start VPN: ${e.message}`);
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Crashed, e.message);
            this.kernelCrashed = true;
            await vpnExtension.stopVpnExtensionAbility(want);
            return false;
        }

        Logger.Info(TAG, `Started VPN on ${tunFd}`)
        CommonEventUtils.publishKernelErrorEvent(KernelEventType.Started);
        return true;
    }

    async onDestroy() {
        if (!this.kernelCrashed) {
            CommonEventUtils.publishKernelErrorEvent(KernelEventType.Stopped);
        }
        native.stopTun()
        if (this.vpnConnection) {
            try {
                await this.vpnConnection.destroy()
            } catch (error) {
                Logger.Error(TAG, `failed to destroy vpnConnection: ${JSON.stringify(error)}`);
            }
        }
        Logger.Info(TAG, `Stopped VPN`)
    }
}
