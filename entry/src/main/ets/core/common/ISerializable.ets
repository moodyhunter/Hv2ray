import Logger from "../../utils/Logging";

const TAG = 'common/ISerializable';
const DEBUG_SERDE = false;

export abstract class ISerializable {
    private readonly className: string;
    constructor(className: string) {
        this.className = className;
    }

    public Serialize(): object {
        const obj = this.doSerialize();
        if (DEBUG_SERDE) {
            Logger.Warn(TAG, `serialized ${this.className} into: {${JSON.stringify(obj)}}`);
        }
        return obj;
    }

    public Fill(input: object) {
        if (DEBUG_SERDE) {
            Logger.Warn(TAG, `filling ${this.className} into: {${JSON.stringify(input)}}`);
        }
        this.doFill(input);
    }

    protected abstract doSerialize(): object;
    protected abstract doFill(input: object): void;
}
