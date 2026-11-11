import { CIDRObject, ConfigRoot, GeoIP, Inbound, JsonValue, Outbound } from "./Config";
import { parseCidr, WireGuardSettings } from "./WgSettings";
import Logger from "../../utils/Logging";

const TAG = 'config/Generation';

export const TUN_INTERFACE_MTU = 1500;

export class ConfigurationBuilder {
    private configRoot: Required<ConfigRoot>;

    constructor(input: ConfigRoot) {
        // structuredClone 在本工程 SDK 的 ArkTS 里不存在（Cannot find name 'structuredClone'），
        // 所以这里只能用 JSON 往返做深拷贝；code-linter 的 bad-deep-clone-check 因此消不掉。
        const configRoot: ConfigRoot = JSON.parse(JSON.stringify(input));
        if (configRoot.inbounds === undefined) {
            configRoot.inbounds = [];
        }
        if (configRoot.outbounds === undefined) {
            configRoot.outbounds = [];
        }
        if (configRoot.router === undefined) {
            configRoot.router = { domainStrategy: 'IpIfNonMatch', rule: [] };
        }
        if (configRoot.services === undefined) {
            configRoot.services = {};
        }
        this.configRoot = configRoot as Required<ConfigRoot>;
    }

    addStatsApi(): void {
        const API_INBOUND_TAG = 'api-inbound';
        const API_OUTBOUND_TAG = 'api-outbound';
        const statsInbound: Inbound = {
            listen: '127.0.0.1',
            port: '18888',
            settings: {
                'networks': ['TCP'],
                "address": "127.0.0.1"
            },
            protocol: 'dokodemo-door',
            tag: API_INBOUND_TAG,
        };

        const commander: Record<string, JsonValue> = {
            'name': ['stats'],
            'tag': API_OUTBOUND_TAG,
        };
        const policy: Record<string, JsonValue> = {
            'system': {
                'stats': {
                    "inboundUplink": true,
                    "inboundDownlink": true,
                    "outboundUplink": true,
                    "outboundDownlink": true,
                }
            },
        };


        this.configRoot.inbounds.push(statsInbound);
        this.configRoot.services['commander'] = commander;
        this.configRoot.services['stats'] = {};
        this.configRoot.services['policy'] = policy;
        this.configRoot.router.rule.unshift({
            tag: API_OUTBOUND_TAG,
            inboundTag: [API_INBOUND_TAG]
        });

    }

    addTunInbound(fdPlaceholder: string) {
        this.configRoot.services['tun'] = {
            "name": fdPlaceholder,
            "mtu": TUN_INTERFACE_MTU,
            "tag": "tun",
            "ips": [
                {
                    "ip": [192, 18, 0, 1],
                    "prefix": 24
                }
            ],
            "routes": [
                {
                    "ip": [0, 0, 0, 0],
                    "prefix": 0
                }
            ],
            "enablePromiscuousMode": true,
            "enableSpoofing": true,
            "sniffingSettings": {
                enabled: true,
                destinationOverride: ["http", "tls", "quic"],
                metadataOnly: false,
            }
        };
    }

    addHttpInbound(): void {
        const httpInbound: Inbound = {
            protocol: 'http',
            tag: 'http-in',
            listen: '0.0.0.0',
            port: '18888'
        };
        this.configRoot.inbounds.push(httpInbound);
    }

    addFreedomOutbound(prepend: boolean = false): void {
        const directOutbound: Outbound = {
            protocol: 'freedom',
            tag: 'direct',
            settings: {}
        };
        if (prepend) {
            this.configRoot.outbounds.unshift(directOutbound);
        } else {
            this.configRoot.outbounds.push(directOutbound);
        }
    }

    addRules(): void {
        // return;
        this.configRoot.router.rule.push({
            tag: 'direct',
            inboundTag: ['tun'],
            geoDomain: [{
                code: 'cn',
                filePath: '/data/storage/el2/base/files/geosite.dat',
            }]
        });
        this.configRoot.router.rule.push({
            tag: 'direct',
            inboundTag: ['tun'],
            geoip: [{
                code: 'cn',
                filePath: '/data/storage/el2/base/files/geoip.dat',
            }]
        });
    }

    addWireguard(wg: WireGuardSettings): void {
        if (wg.privateKey.length === 0 || wg.peerPublicKey.length === 0
            || wg.peerEndpoint.length === 0 || wg.localIp.length === 0) {
            // WireGuard is not configured yet; handing the kernel an empty key or
            // endpoint would fail when the outbound starts.
            Logger.Warn(TAG, `WireGuard settings incomplete, skipping wg-outbound`);
            return;
        }

        const CIDRs: CIDRObject[] = [];
        for (const route of wg.routes) {
            const cidr = parseCidr(route);
            if (cidr === undefined) {
                Logger.Error(TAG, `invalid CIDR '${route}', ignored`);
                continue;
            }
            CIDRs.push(cidr);
        }
        if (CIDRs.length === 0) {
            // Without routes there is nothing to steer into the WireGuard outbound.
            Logger.Warn(TAG, `no valid WireGuard route configured, skipping wg-outbound`);
            return;
        }

        this.configRoot.outbounds.push({
            tag: 'wg-outbound',
            protocol: 'wireguard',
            settings: {
                "wgDevice": {
                    "privateKey": wg.privateKey,
                    "mtu": wg.mtu,
                    "peers": [
                        {
                            "publicKey": wg.peerPublicKey,
                            "endpoint": wg.peerEndpoint,
                            "allowedIps": CIDRs.map((cidr: CIDRObject) => {
                                return `${cidr.ipAddr}/${cidr.prefix}`;
                            }),
                            "persistentKeepaliveInterval": wg.keepaliveInterval
                        }
                    ]
                },
                "stack": {
                    "mtu": wg.mtu,
                    "ips": [
                        { "ipAddr": wg.localIp, "prefix": 32 },
                    ],
                    "routes": CIDRs,
                    "dualStackUdp": true
                },
                "listenOnSystemNetwork": true,
                "domainStrategy": "USE_IP"
            },
        });

        const gepIp: GeoIP = {
            cidr: CIDRs,
            filePath: ''
        };
        this.configRoot.router.rule.unshift({
            'inboundTag': ['tun'],
            tag: 'wg-outbound',
            geoip: [gepIp]
        })

    }

    build(): ConfigRoot {
        return this.configRoot;
    }
}
