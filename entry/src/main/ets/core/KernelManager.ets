import { ConfigRoot } from "./config/Config";

@ObservedV2
export class KernelManagerImpl {
    private activeConfig_: Optional<ConfigRoot> = undefined;

    constructor() {
    }

    public get activeConfig(): ConfigRoot | undefined {
        return this.activeConfig_;
    }
}

export const KernelManager = new KernelManagerImpl();
