import { application } from "@kit.AbilityKit";
import { DEBUG } from "BuildProfile";
import Logger from "../../utils/Logging";
import fs from '@ohos.file.fs';
import { Config } from "./Config";
import { IGroup, loadFromFile, saveToFile } from "./ConfigCommon";

const TAG = 'config/ConfigManager';
const CONFIG_FILES_PATH_PREFIX = DEBUG ? 'config-debug' : 'config';
const CONNECTIONS_FILE = 'connections.json';
const GROUPS_FILE = 'groups.json';

interface GroupConfigRoot {
    groups: IGroup[];
}

@ObservedV2
export class ConfigManagerImpl {
    private readonly configPathBase: string = '/data/storage/el2/base/files/' + CONFIG_FILES_PATH_PREFIX;
    private connections: Map<string, Config> = new Map();
    private groups: Map<string, IGroup> = new Map();

    constructor() {
        try {
            const context = application.getApplicationContext();
            this.configPathBase = context.filesDir + '/' + CONFIG_FILES_PATH_PREFIX;
        } catch (error) {
            Logger.Error(TAG, `failed to get filesDir, using '${this.configPathBase}'`);
        }
    }

    public async loadConfigurations(): Promise<void> {
        await fs.mkdir(this.configPathBase, true).catch((e: BusinessError) => {
            Logger.Error(TAG, `failed to make configuration dir: ${JSON.stringify(e)}`)
        });

        let groupRoot = await this.loadConfigFromFile<GroupConfigRoot>(GROUPS_FILE);
        if (groupRoot) {
            for (let group of groupRoot.groups) {
                this.groups.set(group.id, group);
            }
        }
    }

    private async loadConfigFromFile<T>(fileName: string): Promise<T | undefined> {
        return await loadFromFile(this.configPathBase + '/' + fileName);
    }

    private async writeConfigToFile<T>(t: T, fileName: string): Promise<void> {
        await saveToFile(t, this.configPathBase + '/' + fileName);
    }

    public async saveConfigurations() {
        Logger.Info(TAG, `saveConfigurations in`)
        let groupRoot: GroupConfigRoot = {
            groups: Array.from(this.groups.values()),
        }

        this.writeConfigToFile(groupRoot, GROUPS_FILE);
    }
}


export const ConfigManager = new ConfigManagerImpl();
