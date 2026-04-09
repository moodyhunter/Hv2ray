// Credit: gcc & DuckSoft from Qv2ray Workgroup

import { IShareLinkImporter, IShareLinkImporterResult } from './ShareLinkIO';
import { url } from '@kit.ArkTS';
import Logger from '../../utils/Logging';
import { Utils } from '../../utils/Common';
import { JsonValue, Outbound, StreamObject } from '../config/Config';

const TAG = 'Core/ShareLink/VMess';

interface ILegacyVMessLink {
    v?: string; // "2"
    ps: string; // name
    add: string; // server address
    port: string; // port
    id: string; // vmess uuid
    aid: string; // vmess alterid
    scy?: string, // security
    net: string; // transport
    type: string; // ???
    host: string; // ???
    path: string; // gRPC path
    tls: string; // use TLS? "tls"
    sni: string; // TLS SNI
    alpn?: string; // TLS ALPN
    fp?: string; // fingerprint
}

type ProtocolDecoder = (config: ILegacyVMessLink) => Record<string, JsonValue>;

export class VMessShareLinkImporter implements IShareLinkImporter {
    public readonly name: string = 'vmess';

    private static readonly TRANSPORT_DECODER_MAP: Record<string, ProtocolDecoder> = {
        'tcp': VMessShareLinkImporter.decodeTransportTcp,
        'http': VMessShareLinkImporter.decodeTransportHttp,
        'h2': VMessShareLinkImporter.decodeTransportHttp,
        'ws': VMessShareLinkImporter.decodeTransportWs,
        'kcp': VMessShareLinkImporter.decodeTransportKcp,
        'quic': VMessShareLinkImporter.decodeTransportQuic,
        'grpc': VMessShareLinkImporter.decodeTransportGrpc,
    };

    static decodeTransportTcp(config: ILegacyVMessLink): Record<string, JsonValue> {
        return {};
    }

    static decodeTransportHttp(config: ILegacyVMessLink): Record<string, JsonValue> {
        return {};
    }

    static decodeTransportWs(config: ILegacyVMessLink): Record<string, JsonValue> {
        return {};
    }

    static decodeTransportKcp(config: ILegacyVMessLink): Record<string, JsonValue> {
        return {};
    }

    static decodeTransportQuic(config: ILegacyVMessLink): Record<string, JsonValue> {
        return {};
    }

    static decodeTransportGrpc(config: ILegacyVMessLink): Record<string, JsonValue> {
        return { 'serviceName': config.path };
    }

    matcher(link: string): boolean {
        try {
            const uriObject = url.URL.parseURL(link);
            const expectPureBase64 = !uriObject.hostname.includes('.');
            return uriObject.protocol === 'vmess:' && expectPureBase64;
        } catch (error) {
            return false;
        }
    }

    decode(link: string): IShareLinkImporterResult | undefined {
        const linkObject = this.tryParseVMessLink(link);
        if (!linkObject) {
            return undefined;
        }

        const stream = this.doDecodeStream(linkObject);

        const vmessSettings: Record<string, JsonValue> = {
            'address': linkObject.add,
            'port': parseInt(linkObject.port),
            'uuid': linkObject.id,
        }

        let outbound: Outbound = {
            protocol: 'vmess',
            settings: vmessSettings,
            sendThrough: '0.0.0.0',
            tag: 'outbound',
            streamSettings: stream,
        };
        return { name: linkObject.ps, outbound: outbound };
    }

    private doDecodeStream(linkObject: ILegacyVMessLink): StreamObject {
        const decoder = VMessShareLinkImporter.TRANSPORT_DECODER_MAP[linkObject.net];
        if (!decoder) {
            Logger.Error(TAG, `unsupported transport: ${linkObject.net}`);
            return new StreamObject();
        }

        if (linkObject.net === 'h2') {
            // damn vmess:// just don't write 'http' properly
            linkObject.net = 'http';
        }

        const stream = new StreamObject();
        stream.transport = linkObject.net;
        stream.transportSettings = decoder(linkObject);

        if (linkObject.tls === 'tls') {
            stream.security = 'tls';
            if (!linkObject.sni && linkObject.host) {
                linkObject.sni = linkObject.host;
            }
            stream.securitySettings['serverName'] = linkObject.sni;
        }
        return stream;
    }

    private tryParseVMessLink(link: string): ILegacyVMessLink | undefined {
        const mainPart = link.substring('vmess://'.length);
        for (let i = 0; i <= 3; i++) {
            try {
                const decoded = Utils.base64Decode(mainPart + '='.repeat(i));
                const item: ILegacyVMessLink = JSON.parse(decoded);
                return item;
            } catch (e) {
                continue;
            }
        }

        Logger.Error(TAG, `failed to parse`);
        return undefined;
    }
}


