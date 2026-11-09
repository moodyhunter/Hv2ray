// Basic scalar JSON types
export type JsonBasicValue = string | number | boolean;

export class JsonObject {
    [key: string]: JsonValue | JsonValue[];
}

export type JsonValue =
    | JsonBasicValue
    | JsonBasicValue[]
    | JsonObject
    | undefined;

