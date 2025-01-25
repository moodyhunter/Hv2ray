// SPDX-License-Identifier: GPL-3.0-or-later
import { vpnExtension, VpnExtensionAbility } from '@kit.NetworkKit';
import { Want } from '@kit.AbilityKit';
import Logging from '../utils/Logging';
import Hv2rayPreferences from '../utils/Preferences';
import native from 'libnative.so';
import { commonEventManager } from '@kit.BasicServicesKit';
import { Constants, Stat } from '../utils/Common';

const TAG = "Hv2ray-VpnAbility";
const TUN_IP = "198.18.0.1";

enum AddressFamily {
    IPv4 = 1,
    IPv6 = 2,
}

class Address {
    address: string;
    family: AddressFamily; // 1 for IPv4, 2 for IPv6

    constructor(address: string, family: number) {
        this.address = address;
        this.family = family;
    }
}

class AddressWithPrefix {
    address: Address;
    prefixLength: number;

    constructor(address: Address, prefixLength: number) {
        this.address = address;
        this.prefixLength = prefixLength;
    }
}

class VpnConfig {
    addresses: AddressWithPrefix[];
    mtu: number;
    dnsAddresses: string[];
    trustedApplications: string[];

    constructor(tunIp: string, trustedApplications: string[]) {
        this.addresses = [
            new AddressWithPrefix(new Address(tunIp, AddressFamily.IPv4), 24)
        ];
        this.trustedApplications = trustedApplications;
        this.mtu = 1500;
        this.dnsAddresses = ["1.1.1.1"];
    }
}

export class VpnAbility extends VpnExtensionAbility {
    vpnConnection: vpnExtension.VpnConnection | null = null;

    async onCreate(want: Want) {
        if (this.vpnConnection == null) {
            this.vpnConnection = vpnExtension.createVpnConnection(this.context);
        }

        const TRUSTED_APPS = [
            "com.easy.hmos.abroad"
        ];

        let config = new VpnConfig(TUN_IP, TRUSTED_APPS);
        let tunFd = await this.vpnConnection.create(config);
        if (tunFd < 0) {
            Logging.Error(TAG, `Failed to create VPN: ${tunFd}`);
            return false;
        }

        Logging.Info(TAG, `Starting VPN on ${tunFd}`);

        let socks5Port = Hv2rayPreferences.GetSocks5Port(this.context);

        try {
            let MY_CONFIG = Hv2rayPreferences.GetConfig(this.context);
            native.startVCore(socks5Port, MY_CONFIG);
            native.startTun(tunFd, socks5Port);
            native.onStatisticsEvent(1, (stats: Stat) => {
                let options: commonEventManager.CommonEventPublishData = {
                    bundleName: "me.moody.hv2ray",
                    data: JSON.stringify(stats),
                };

                commonEventManager.publish(Constants.EVENT_NAME, options, (err, _data) => {
                    if (err && err.code) {
                        Logging.Error(TAG, `Failed to publish event: ${JSON.stringify(err)}`);
                        return;
                    }
                });
            });
        } catch (e) {
            Logging.Error(TAG, `Failed to start VPN: ${e}`);
            await vpnExtension.stopVpnExtensionAbility(want);
            return false;
        }

        Logging.Info(TAG, `Started VPN on ${tunFd}`)
        return true;
    }

    async onDestroy() {
        native.stopVCore()
        native.stopTun()
        if (this.vpnConnection) {
            this.vpnConnection.destroy()
        }
        Logging.Info(TAG, `Stopped VPN`)
    }
}
