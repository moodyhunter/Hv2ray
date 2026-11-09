import Logger from "../../utils/Logging";
import { ISerializable } from "../common/ISerializable";
import { MetaDataKey, ValidMetaDataKey } from "./ConfigMetadataTypes";

const TAG = 'config/Metadata';

export class ConfigMetadata extends ISerializable {
    private metadata: Map<MetaDataKey, string> = new Map();

    constructor() {
        super('ConfigMetadata');
    }

    protected doSerialize(): object {
        const result: object = new Object();
        for (const item of this.metadata) {
            if (typeof item[1] !== 'string') {
                Logger.Error(TAG, `unsupported metadata value type: ${typeof item[1]}`);
                continue;
            }
            if (!ValidMetaDataKey.includes(item[0])) {
                Logger.Warn(TAG, `unsupported metadata key: ${item[0]}, keeping anyways`);
            }
            result[item[0]] = item[1];
        }
        return result;
    }

    protected doFill(input: object): void {
        this.metadata.clear();
        if (input === undefined) {
            return;
        }
        for (const key of Object.keys(input)) {
            this.metadata.set(key as MetaDataKey, input[key] as string);
        }
    }
}