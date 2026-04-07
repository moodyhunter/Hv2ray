import { Config } from "./config/Config";

@ObservedV2
export class KernelManagerImpl {
    private activeConfig_: Optional<Config> = undefined;

    constructor() {
    }

    public get activeConfig(): Config | undefined {
        return this.activeConfig_;
    }
}

export const KernelManager = new KernelManagerImpl();
