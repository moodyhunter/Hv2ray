import { ISerializable } from "../common/ISerializable";
import { ConfigMetadata } from "./ConfigMetadata";

@ObservedV2
export class Connection extends ISerializable {
    id: string = '<unknown>';
    @Trace name: string = '<unknown>';
    metadata: ConfigMetadata = new ConfigMetadata();

    constructor() {
        super('Connection')
    }

    protected doFill(input: object): void {
        this.id = input['id'] as string;
        this.name = input['name'] as string;
        this.metadata.Fill(input['metadata']);
    }

    protected doSerialize(): object {
        let result: object = new Object();
        result['id'] = this.id;
        result['name'] = this.name;
        result['metadata'] = this.metadata.Serialize();
        return result;
    }
}
