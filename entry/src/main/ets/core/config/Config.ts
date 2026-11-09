import { JsonObject, JsonValue } from "./ConfigDefs";

export { JsonValue };

type DestOverrideType = "http" | "tls" | "quic" | "fakedns" | "fakedns+others";
type DomainStrategy = "AsIs" | "UseIP" | "IpIfNonMatch" | "IpOnDemand";

export type SniffingObjectInit = {
    enabled: boolean;
    destOverride: DestOverrideType[];
    metadataOnly: boolean;
};

export class SniffingObject extends JsonObject {
    enabled!: boolean;
    destOverride!: DestOverrideType[];
    metadataOnly!: boolean;

    constructor(init?: Partial<SniffingObjectInit>) {
        super();
        if (!init) return;
        if (init.enabled !== undefined) this.enabled = init.enabled;
        if (init.destOverride !== undefined) this.destOverride = init.destOverride;
        if (init.metadataOnly !== undefined) this.metadataOnly = init.metadataOnly;
    }
}

export type InboundInit = {
    protocol: string;
    settings?: JsonObject;
    tag: string;
    port: string;
    listen: string;
    sniffing?: SniffingObject;
};

export class Inbound extends JsonObject {
    protocol!: string;
    settings?: JsonObject;

    tag!: string;
    port!: string;
    listen!: string;
    sniffing?: SniffingObject;

    constructor(init?: Partial<InboundInit>) {
        super();
        if (!init) return;
        if (init.protocol !== undefined) this.protocol = init.protocol;
        if (init.settings !== undefined) this.settings = init.settings;
        if (init.tag !== undefined) this.tag = init.tag;
        if (init.port !== undefined) this.port = init.port;
        if (init.listen !== undefined) this.listen = init.listen;
        if (init.sniffing !== undefined) this.sniffing = init.sniffing;
    }
}

export type StreamObjectInit = {
    transport: string;
    transportSettings: JsonObject;
    security: string;
    securitySettings?: JsonObject;
};

export class StreamObject extends JsonObject {
    transport!: string;
    transportSettings!: JsonObject;
    security!: string;
    securitySettings?: JsonObject;

    constructor(init?: Partial<StreamObjectInit>) {
        super();
        if (!init) return;
        if (init.transport !== undefined) this.transport = init.transport;
        if (init.transportSettings !== undefined) this.transportSettings = init.transportSettings;
        if (init.security !== undefined) this.security = init.security;
        if (init.securitySettings !== undefined) this.securitySettings = init.securitySettings;
    }
}

export type OutboundInit = {
    tag: string;
    protocol: string;
    settings: JsonObject;
    sendThrough?: string;
    streamSettings?: StreamObject;
};

export class Outbound extends JsonObject {
    tag!: string;
    protocol!: string;
    settings!: JsonObject;
    sendThrough?: string;
    streamSettings?: StreamObject;

    constructor(init?: Partial<OutboundInit>) {
        super();
        if (!init) return;
        if (init.tag !== undefined) this.tag = init.tag;
        if (init.protocol !== undefined) this.protocol = init.protocol;
        if (init.settings !== undefined) this.settings = init.settings;
        if (init.sendThrough !== undefined) this.sendThrough = init.sendThrough;
        if (init.streamSettings !== undefined) this.streamSettings = init.streamSettings;
    }
}

export type TransportInit = {
    protocol: string;
    config: string;
};

export class Transport extends JsonObject {
    protocol!: string;
    config!: string;

    constructor(init?: Partial<TransportInit>) {
        super();
        if (!init) return;
        if (init.protocol !== undefined) this.protocol = init.protocol;
        if (init.config !== undefined) this.config = init.config;
    }
}

export type SecurityInit = {
    protocol: string;
    config: string;
};

export class Security extends JsonObject {
    protocol!: string;
    config!: string;

    constructor(init?: Partial<SecurityInit>) {
        super();
        if (!init) return;
        if (init.protocol !== undefined) this.protocol = init.protocol;
        if (init.config !== undefined) this.config = init.config;
    }
}

export type DomainObjectInit = {
    type: "Plain" | "Regex" | "RootDomain" | "Full";
    value: string;
};

export class DomainObject extends JsonObject {
    type!: "Plain" | "Regex" | "RootDomain" | "Full";
    value!: string;

    constructor(init?: Partial<DomainObjectInit>) {
        super();
        if (!init) return;
        if (init.type !== undefined) this.type = init.type;
        if (init.value !== undefined) this.value = init.value;
    }
}

export type GeoDomainInit = {
    code: string;
    filePath?: string;
};

export class GeoDomain extends JsonObject {
    code!: string;
    filePath?: string;

    constructor(init?: Partial<GeoDomainInit>) {
        super();
        if (!init) return;
        if (init.code !== undefined) this.code = init.code;
        if (init.filePath !== undefined) this.filePath = init.filePath;
    }
}

export type CIDRObjectInit = {
    ipAddr: string;
    prefix: number;
};

export class CIDRObject extends JsonObject {
    ipAddr!: string;
    prefix!: number;

    constructor(init?: Partial<CIDRObjectInit>) {
        super();
        if (!init) return;
        if (init.ipAddr !== undefined) this.ipAddr = init.ipAddr;
        if (init.prefix !== undefined) this.prefix = init.prefix;
    }
}

export type GeoIPInit = {
    cidr?: CIDRObject[];
    inverseMatch?: boolean;
    code?: string;
    filePath?: string;
};

export class GeoIP extends JsonObject {
    cidr?: CIDRObject[];
    inverseMatch?: boolean;
    code?: string;
    filePath?: string;

    constructor(init?: Partial<GeoIPInit>) {
        super();
        if (!init) return;
        if (init.cidr !== undefined) this.cidr = init.cidr;
        if (init.inverseMatch !== undefined) this.inverseMatch = init.inverseMatch;
        if (init.code !== undefined) this.code = init.code;
        if (init.filePath !== undefined) this.filePath = init.filePath;
    }
}

export type RuleInit = {
    tag: string;
    inboundTag: string[];
    domain?: DomainObject[];
    geoDomain?: GeoDomain[];
    geoip?: GeoIP[];
};

export class Rule extends JsonObject {
    tag!: string;
    inboundTag!: string[];
    domain?: DomainObject[];
    geoDomain?: GeoDomain[];
    geoip?: GeoIP[];

    constructor(init?: Partial<RuleInit>) {
        super();
        if (!init) return;
        if (init.tag !== undefined) this.tag = init.tag;
        if (init.inboundTag !== undefined) this.inboundTag = init.inboundTag;
        if (init.domain !== undefined) this.domain = init.domain;
        if (init.geoDomain !== undefined) this.geoDomain = init.geoDomain;
        if (init.geoip !== undefined) this.geoip = init.geoip;
    }
}

export type RouterInit = {
    domainStrategy: DomainStrategy;
    rule: Rule[];
    balancingRule?: string[];
};

export class Router extends JsonObject {
    domainStrategy!: DomainStrategy;
    rule!: Rule[];
    balancingRule?: string[];

    constructor(init?: Partial<RouterInit>) {
        super();
        if (!init) return;
        if (init.domainStrategy !== undefined) this.domainStrategy = init.domainStrategy;
        if (init.rule !== undefined) this.rule = init.rule;
        if (init.balancingRule !== undefined) this.balancingRule = init.balancingRule;
    }
}

export type ConfigRootInit = {
    inbounds?: Inbound[];
    outbounds?: Outbound[];
    services?: JsonObject;
    router?: Router;
};

export class ConfigRoot extends JsonObject {
    inbounds?: Inbound[];
    outbounds?: Outbound[];
    services?: JsonObject;
    router?: Router;

    constructor(init?: Partial<ConfigRootInit>) {
        super();
        if (!init) return;
        if (init.inbounds !== undefined) this.inbounds = init.inbounds;
        if (init.outbounds !== undefined) this.outbounds = init.outbounds;
        if (init.services !== undefined) this.services = init.services;
        if (init.router !== undefined) this.router = init.router;
    }
}
