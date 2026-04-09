import { application } from "@kit.AbilityKit";
import { DEBUG } from "BuildProfile";
import Logger from "../../utils/Logging";
import fs from '@ohos.file.fs';
import { ConfigRoot } from "./Config";
import { IConnection, IGroup, loadFromFile, saveToFile } from "./ConfigCommon";

const TAG = 'config/ConfigManager';
const CONFIG_FILES_PATH_PREFIX = DEBUG ? 'config-debug' : 'config';
const CONNECTIONS_PATH_DIR = 'connections';
const CONFIG_FILE = 'groups.json';

interface Hv2rayConfigRoot {
    groups: IGroup[];
    connections: IConnection[];
}

function generateRandomString(length: number = 16) {
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < length; i++) {
        result += characters.charAt(Math.floor(Math.random() * characters.length));
    }
    return result;
}

@ObservedV2
export class ConfigManagerImpl {
    private readonly configPathBase: string = '/data/storage/el2/base/files/' + CONFIG_FILES_PATH_PREFIX;
    @Trace private groups: Map<string, IGroup> = new Map();
    @Trace private connections: Map<string, IConnection> = new Map();

    constructor() {
        try {
            const context = application.getApplicationContext();
            this.configPathBase = context.filesDir + '/' + CONFIG_FILES_PATH_PREFIX;
        } catch (error) {
            Logger.Error(TAG, `failed to get filesDir, using '${this.configPathBase}'`);
        }
    }

    public get allGroups() {
        return this.groups;
    }

    public getConnection(connId: string): IConnection | undefined {
        return this.connections.get(connId);
    }

    private safeMkdir(path: string) {
        try {
            fs.mkdirSync(path, true);
        } catch (error) {
            // 13900015: already exists
            if (error.code !== 13900015) {
                Logger.Error(TAG, `failed to make configuration dir: ${JSON.stringify(error)}`);
            }
        }
    }

    private get connectionsDir(): string {
        return this.configPathBase + '/' + CONNECTIONS_PATH_DIR;
    }

    public async loadConfigurations(): Promise<void> {
        this.safeMkdir(this.configPathBase);
        this.safeMkdir(this.connectionsDir);

        let root = await this.loadConfigFromFile<Hv2rayConfigRoot>(CONFIG_FILE);
        if (root) {
            for (let group of root.groups) {
                this.groups.set(group.id, group);
            }

            for (let connection of root.connections) {
                this.connections.set(connection.id, connection);
            }
        }

        this.ensureDefaultGroups();
    }

    private ensureDefaultGroups() {
        // check if 'default' group exists
        if (!this.groups.has('default')) {
            const defaultGroup: IGroup = {
                id: 'default',
                name: 'Default',
                connections: []
            };

            this.groups.set(defaultGroup.id, defaultGroup);
        }

        // check if 'subscription' group exists
        if (!this.groups.has('subscription')) {
            const subscriptionGroup: IGroup = {
                id: 'subscription',
                name: 'Subscription',
                connections: []
            };

            this.groups.set(subscriptionGroup.id, subscriptionGroup);
        }
    }

    public async addConnectionToGroup(connectionName: string, groupId: string, content: ConfigRoot) {
        const group = this.groups.get(groupId);
        if (!group) {
            Logger.Error(TAG, `group ${groupId} does not exist`);
            return;
        }

        let conn: IConnection = {
            id: generateRandomString(),
            name: connectionName,
        };

        this.connections.set(conn.id, conn);
        group.connections.push(conn.id);
        await this.writeConnectionToFile(conn.id, content);
        await this.saveConfigurations();
    }

    private async loadConfigFromFile<T>(fileName: string): Promise<T | undefined> {
        return await loadFromFile(this.configPathBase + '/' + fileName);
    }

    public async writeConfigToFile<T>(t: T, fileName: string): Promise<void> {
        await saveToFile(t, this.configPathBase + '/' + fileName);
    }

    public async loadConnectionFromFile(connId: string): Promise<ConfigRoot | undefined> {
        return await loadFromFile<ConfigRoot>(this.connectionsDir + '/' + connId + '.json');
    }

    private async writeConnectionToFile(connId: string, content: ConfigRoot): Promise<void> {
        await saveToFile(content, this.connectionsDir + '/' + connId + '.json');
    }

    public async saveConfigurations() {
        Logger.Info(TAG, `saveConfigurations in`)
        let root: Hv2rayConfigRoot = {
            groups: Array.from(this.groups.values()),
            connections: Array.from(this.connections.values()),
        }

        this.writeConfigToFile(root, CONFIG_FILE);
    }
}


export const ConfigManager = new ConfigManagerImpl();
