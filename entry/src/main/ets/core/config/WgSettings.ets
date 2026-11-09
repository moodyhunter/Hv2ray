// SPDX-License-Identifier: GPL-3.0-or-later
import { ISerializable } from "../common/ISerializable";
import { CIDRObject } from "./Config";
import { Utils } from "../../utils/Common";

/**
 * Parses a CIDR notation ("100.64.0.0/10") into the config object used by
 * the WireGuard outbound. Returns undefined for anything malformed.
 */
export function parseCidr(cidr: string): CIDRObject | undefined {
    const separator = cidr.indexOf('/');
    if (separator < 0) {
        return undefined;
    }

    const ipAddr = cidr.substring(0, separator)
        .trim();
    const prefixText = cidr.substring(separator + 1)
        .trim();
    if (ipAddr.length === 0 || !Utils.isUnsignedDecimal(prefixText)) {
        return undefined;
    }

    // A colon in the address is the only marker of an IPv6 prefix range here.
    const maxPrefix = ipAddr.indexOf(':') >= 0 ? 128 : 32;
    const prefix = parseInt(prefixText);
    if (prefix > maxPrefix) {
        return undefined;
    }

    return { ipAddr: ipAddr, prefix: prefix };
}

/**
 * User-editable WireGuard parameters, persisted in settings.json.
 * 'routes' are CIDR notations ("10.0.0.0/24") used both as the peer's
 * allowedIPs and as the local stack routes / geoip matching set.
 *
 * Keys, endpoints and addresses default to empty on purpose so that no
 * personal WireGuard information ends up in the source; they are filled in
 * the Settings page. Only protocol-neutral values keep a default.
 */
export class WireGuardSettings extends ISerializable {
    privateKey: string = '';
    peerPublicKey: string = '';
    peerEndpoint: string = '';
    localIp: string = '';
    mtu: number = 1420;
    keepaliveInterval: number = 25;
    routes: string[] = [];

    constructor() {
        super('WireGuardSettings');
    }

    protected doSerialize(): object {
        const result: object = new Object();
        result['privateKey'] = this.privateKey;
        result['peerPublicKey'] = this.peerPublicKey;
        result['peerEndpoint'] = this.peerEndpoint;
        result['localIp'] = this.localIp;
        result['mtu'] = this.mtu;
        result['keepaliveInterval'] = this.keepaliveInterval;
        result['routes'] = this.routes;
        return result;
    }

    protected doFill(input: object): void {
        if (input === undefined) {
            return;
        }
        if (typeof input['privateKey'] === 'string') {
            this.privateKey = input['privateKey'] as string;
        }
        if (typeof input['peerPublicKey'] === 'string') {
            this.peerPublicKey = input['peerPublicKey'] as string;
        }
        if (typeof input['peerEndpoint'] === 'string') {
            this.peerEndpoint = input['peerEndpoint'] as string;
        }
        if (typeof input['localIp'] === 'string') {
            this.localIp = input['localIp'] as string;
        }
        if (typeof input['mtu'] === 'number') {
            this.mtu = input['mtu'] as number;
        }
        if (typeof input['keepaliveInterval'] === 'number') {
            this.keepaliveInterval = input['keepaliveInterval'] as number;
        }
        if (input['routes'] !== undefined) {
            const routes = input['routes'] as string[];
            this.routes = [];
            for (const route of routes) {
                if (typeof route === 'string' && route.length > 0) {
                    this.routes.push(route);
                }
            }
        }
    }
}
