@ObservedV2
export class Inbound {
    @Trace protocol: string = '';
    @Trace config: string = '{}';
    @Trace tag: string = '';
}

@ObservedV2
export class Outbound {
    @Trace protocol: string = '';
    @Trace config: string = '{}';
    @Trace tag: string = '';
}

@ObservedV2
export class Transport {
    @Trace protocol: string = '';
    @Trace config: string = '{}';
}

@ObservedV2
export class Security {
    @Trace protocol: string = '';
    @Trace config: string = '{}';
}

@ObservedV2
export class Config {

}
