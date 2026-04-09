import fs from '@ohos.file.fs';
import Logger from '../../utils/Logging';
import { util } from '@kit.ArkTS';

const TAG = 'config/ConfigCommon';

export interface IGroup {
    id: string;
    name: string;
    connections: string[]; // connection id
}

export interface IConnection {
    id: string;
    name: string;
}

function decodeText(arrayBufer: ArrayBuffer): string {
    const decoder = new util.TextDecoder();
    return decoder.decodeToString(new Uint8Array(arrayBufer));
}

export async function loadFromFile<T>(filePath: string): Promise<T | undefined> {
    let buffer: ArrayBuffer;
    try {
        const file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
        const bufferSize = (await fs.stat(file.fd)).size;
        buffer = new ArrayBuffer(bufferSize)
        const readSize = await fs.read(file.fd, buffer);
        await fs.close(file)
            .catch((e: BusinessError) => {
                Logger.Error(TAG, `failed to close file: ${JSON.stringify(e)}`);
            })
        if (readSize !== bufferSize) {
            Logger.Error(TAG, `read from file failed, expect ${bufferSize}, actural read size ${readSize}`);
            return undefined;
        }
    } catch (error) {
        Logger.Error(TAG, `failed to read from file: ${JSON.stringify(error)}`);
        return undefined;
    }

    const strContent = decodeText(buffer);
    try {
        return JSON.parse(strContent) as T;
    } catch (e) {
        Logger.Error(TAG, `failed to parse JSON`);
        return new Object() as T;
    }
}

export async function saveToFile<T>(t: T, filePath: string) {
    let content = JSON.stringify(t, undefined, 2);
    try {
        const file = await fs.open(filePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        await fs.write(file.fd, content);
        await fs.close(file)
            .catch((e: BusinessError) => {
                Logger.Error(TAG, `failed to close file: ${JSON.stringify(e)}`);
            });
    } catch (error) {
        Logger.Error(TAG, `failed to write to file: ${JSON.stringify(error)}`);
        return;
    }
}