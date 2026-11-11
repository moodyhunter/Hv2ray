import { application } from "@kit.AbilityKit";
import { DEBUG } from "BuildProfile";
import Logger from "../../utils/Logging";
import fs from '@ohos.file.fs';
import { ConfigRoot } from "./Config";
import { IGroup, loadFromFile, saveToFile } from "./ConfigCommon";
import { Ctor } from "../common/SerializableTypes";
import { ISerializable } from "../common/ISerializable";
import { Connection } from "./Connection";
import { WireGuardSettings } from "./WgSettings";

const TAG = 'config/ConfigManager';
const CONFIG_FILES_PATH_PREFIX = DEBUG ? 'config-debug' : 'config';
const CONNECTIONS_PATH_DIR = 'connections';
const CONFIG_FILE = 'groups.json';
const SETTINGS_FILE = 'settings.json';

class Hv2rayConfigRoot extends ISerializable {
    groups: IGroup[];
    connections: Connection[];

    constructor() {
        super('Hv2rayConfigRoot');
        this.groups = [];
        this.connections = [];
    }

    protected doSerialize(): object {
        const obj: object = new Object;
        obj['groups'] = this.groups;
        obj['connections'] = this.connections.map(connection => connection.Serialize());
        return obj;
    }

    protected doFill(input: object): void {
        this.groups = input['groups'] as IGroup[];
        const arrayObj = input['connections'] as object[];
        for (let i = 0; i < arrayObj.length; i++) {
            const obj = arrayObj[i] as object;
            const conn = new Connection();
            conn.Fill(obj);
            this.connections.push(conn);
        }
    }
}

function generateRandomString(length: number = 16) {
    const characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    let result = '';
    for (let i = 0; i < length; i++) {
        result += characters.charAt(Math.floor(Math.random() * characters.length));
    }
    return result;
}

/**
 * Notified whenever the in-memory group/connection set changes, so UI that keeps a
 * derived view of it (the group list on the Home page) can rebuild that view.
 */
export type ConfigChangeListener = () => void;

@ObservedV2
export class ConfigManagerImpl {
    private readonly configPathBase: string = '/data/storage/el2/base/files/' + CONFIG_FILES_PATH_PREFIX;
    @Trace private groups: Map<string, IGroup> = new Map();
    @Trace private connections: Map<string, Connection> = new Map();
    @Trace private wgSettings: WireGuardSettings = new WireGuardSettings();
    private listeners: ConfigChangeListener[] = [];

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

    public get wireGuard(): WireGuardSettings {
        return this.wgSettings;
    }

    public getConnection(connId: string): Connection | undefined {
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

        let root = await this.loadConfigFromFile(Hv2rayConfigRoot, CONFIG_FILE);
        if (root) {
            for (let group of root.groups) {
                this.groups.set(group.id, group);
            }

            for (let connection of root.connections) {
                this.connections.set(connection.id, connection);
            }
        }

        // loadFromFile returns a plain object when settings.json is missing or malformed,
        // in which case the built-in defaults are kept.
        const wgSettings = await this.loadConfigFromFile(WireGuardSettings, SETTINGS_FILE);
        if (wgSettings instanceof WireGuardSettings) {
            this.wgSettings = wgSettings;
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

        let conn = new Connection();
        conn.id = generateRandomString();
        conn.name = connectionName;
        this.connections.set(conn.id, conn);
        group.connections.push(conn.id);
        await this.writeConnectionToFile(conn.id, content);
        await this.saveConfigurations();
        this.notifyChanged();
    }

    public getGroupOfConnection(connId: string): IGroup | undefined {
        for (const group of this.groups.values()) {
            if (group.connections.includes(connId)) {
                return group;
            }
        }
        return undefined;
    }

    public async removeConnection(connId: string): Promise<boolean> {
        if (!this.connections.has(connId)) {
            Logger.Error(TAG, `cannot remove unknown connection ${connId}`);
            return false;
        }

        for (const group of this.groups.values()) {
            const index = group.connections.indexOf(connId);
            if (index >= 0) {
                group.connections.splice(index, 1);
            }
        }
        this.connections.delete(connId);

        try {
            await fs.unlink(this.connectionFilePath(connId));
        } catch (error) {
            Logger.Error(TAG, `failed to remove connection file: ${JSON.stringify(error)}`);
        }

        const persisted = await this.saveConfigurations();
        this.notifyChanged();
        return persisted;
    }

    public async renameConnection(connId: string, name: string): Promise<boolean> {
        const trimmed = name.trim();
        if (trimmed.length === 0) {
            Logger.Error(TAG, `refusing to rename ${connId} to an empty name`);
            return false;
        }

        const conn = this.connections.get(connId);
        if (!conn) {
            Logger.Error(TAG, `cannot rename unknown connection ${connId}`);
            return false;
        }

        conn.name = trimmed;
        const persisted = await this.saveConfigurations();
        this.notifyChanged();
        return persisted;
    }

    public async moveConnection(connId: string, targetGroupId: string): Promise<boolean> {
        const target = this.groups.get(targetGroupId);
        if (!target || !this.connections.has(connId)) {
            Logger.Error(TAG, `cannot move ${connId} to unknown group ${targetGroupId}`);
            return false;
        }

        for (const group of this.groups.values()) {
            const index = group.connections.indexOf(connId);
            if (index >= 0) {
                group.connections.splice(index, 1);
            }
        }
        target.connections.push(connId);

        const persisted = await this.saveConfigurations();
        this.notifyChanged();
        return persisted;
    }

    public async updateConnectionContent(connId: string, content: ConfigRoot): Promise<boolean> {
        if (!this.connections.has(connId)) {
            Logger.Error(TAG, `cannot update content of unknown connection ${connId}`);
            return false;
        }

        const persisted = await this.writeConnectionToFile(connId, content);
        this.notifyChanged();
        return persisted;
    }

    public onChanged(listener: ConfigChangeListener): void {
        this.listeners.push(listener);
    }

    public offChanged(listener: ConfigChangeListener): void {
        const index = this.listeners.indexOf(listener);
        if (index >= 0) {
            this.listeners.splice(index, 1);
        }
    }

    private notifyChanged(): void {
        for (const listener of this.listeners) {
            listener();
        }
    }

    private async loadConfigFromFile<T>(ctor: Ctor<T>, fileName: string): Promise<T | undefined> {
        return await loadFromFile(ctor, this.configPathBase + '/' + fileName);
    }

    public async writeConfigToFile<T>(t: T, fileName: string): Promise<boolean> {
        return await saveToFile(t, this.configPathBase + '/' + fileName);
    }

    private connectionFilePath(connId: string): string {
        return this.connectionsDir + '/' + connId + '.json';
    }

    public async loadConnectionFromFile(connId: string): Promise<ConfigRoot | undefined> {
        return await loadFromFile(ConfigRoot, this.connectionFilePath(connId));
    }

    private async writeConnectionToFile(connId: string, content: ConfigRoot): Promise<boolean> {
        return await saveToFile(content, this.connectionFilePath(connId));
    }

    public async saveConfigurations(): Promise<boolean> {
        Logger.Info(TAG, `saveConfigurations in`)
        let root = new Hv2rayConfigRoot();
        root.groups = Array.from(this.groups.values());
        root.connections = Array.from(this.connections.values());
        return await this.writeConfigToFile(root, CONFIG_FILE);
    }

    public async saveWireGuardSettings(settings: WireGuardSettings): Promise<boolean> {
        Logger.Info(TAG, `saveWireGuardSettings in`)
        const written = await this.writeConfigToFile(settings, SETTINGS_FILE);
        if (!written) {
            Logger.Error(TAG, `failed to persist ${SETTINGS_FILE}, keeping previous settings`);
            return false;
        }
        this.wgSettings = settings;
        return true;
    }
}


export const ConfigManager = new ConfigManagerImpl();
