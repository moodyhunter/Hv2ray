export type JsonValue = string | number | boolean | Record<string, object>;

type DestOverrideType = "http" | "tls" | "quic" | "fakedns" | "fakedns+others";
export class SniffingObject {
    enabled: boolean = false;
    destOverride: DestOverrideType[] = [];
    metadataOnly: boolean = false;
}

export class Inbound {
    protocol: string = '';
    settings: Record<string, JsonValue> = {};

    tag: string = '';
    port: string = '';
    listen: string = '0.0.0.0';
    sniffing: Optional<SniffingObject> = undefined;
}

export class StreamObject {
    transport: string = '';
    transportSettings: Record<string, JsonValue> = {};
    security: string = '';
    securitySettings: Record<string, JsonValue> = {};
}

export class Outbound {
    protocol: string = '';
    settings: Record<string, JsonValue> = {};
    sendThrough: string = '0.0.0.0';
    tag: string = '';
    streamSettings: StreamObject = new StreamObject();
}

export class Transport {
    protocol: string = '';
    config: string = '{}';
}

export class Security {
    protocol: string = '';
    config: string = '{}';
}

type DomainStrategy = 'AsIs' | 'UseIP' | 'IpIfNonMatch' | 'IpOnDemand';

export class DomainObject {
    type: 'Plain' | 'Regex' | 'RootDomain' | 'Full' = 'Plain';
    value: string = '';
}

export class GeoDomain {
    domain: DomainObject = new DomainObject();
    code: string = '';
    filePath: string = '';
}

export class CIDRObject {
    ipAddr: string = '0.0.0.0';
    prefix: number = 0;
}


export class GeoIP {
    cidr: CIDRObject[] = [];
    inverseMatch: boolean = false;
    code: string = '';
    filePath: string = '';
}

export class Rule {
    tag: string = '';
    inboundTag: string[] = [];
    domain: DomainObject[] = [];
    geoDomain: GeoDomain[] = [];
    geoIp: GeoIP[] = [];
}

export class Router {
    domainStrategy: DomainStrategy = 'AsIs';
    rule: string[] = [];
    balancingRule: string[] = [];
}

export class ConfigRoot {
    inbounds: Inbound[] = [];
    outbounds: Outbound[] = [];
}
