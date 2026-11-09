import Logger from '../utils/Logging';
import { Utils } from '../utils/Common';
import { ConfigManager } from '../core/config/ConfigManager';
import { parseCidr, WireGuardSettings } from '../core/config/WgSettings';
import { TUN_INTERFACE_MTU } from '../core/config/Generation';

const TAG = "Hv2ray-Settings"
const LABEL_WIDTH = 160;

@ComponentV2
export struct Settings {
    @Local private wgPrivateKey: string = '';
    @Local private wgPeerPublicKey: string = '';
    @Local private wgPeerEndpoint: string = '';
    @Local private wgLocalIp: string = '';
    @Local private wgMtu: string = '';
    @Local private wgKeepalive: string = '';
    @Local private wgRoutes: string = '';

    aboutToAppear(): void {
        Logger.Info(TAG, `aboutToAppear`);
        this.loadFromManager();
    }

    private loadFromManager(): void {
        const wg: WireGuardSettings = ConfigManager.wireGuard;
        this.wgPrivateKey = wg.privateKey;
        this.wgPeerPublicKey = wg.peerPublicKey;
        this.wgPeerEndpoint = wg.peerEndpoint;
        this.wgLocalIp = wg.localIp;
        this.wgMtu = `${wg.mtu}`;
        this.wgKeepalive = `${wg.keepaliveInterval}`;
        this.wgRoutes = wg.routes.join('\n');
    }

    private parseRoutes(input: string): string[] {
        const result: string[] = [];
        for (const line of input.split('\n')) {
            for (const part of line.split(',')) {
                const route = part.trim();
                if (route.length > 0) {
                    result.push(route);
                }
            }
        }
        return result;
    }

    private parsePositiveInt(input: string): number {
        const text = input.trim();
        if (!Utils.isUnsignedDecimal(text)) {
            return -1;
        }
        const value = parseInt(text);
        if (value <= 0) {
            return -1;
        }
        return value;
    }

    /**
     * Returns the reason why the form cannot be saved, or undefined when
     * every field looks usable.
     */
    private getValidationFailure(): string | undefined {
        if (this.wgPrivateKey.trim().length === 0) {
            return 'Private key must not be empty';
        }
        if (this.wgPeerPublicKey.trim().length === 0) {
            return 'Peer public key must not be empty';
        }
        if (this.wgPeerEndpoint.trim().length === 0) {
            return 'Peer endpoint must not be empty';
        }
        if (this.wgLocalIp.trim().length === 0) {
            return 'Local IP must not be empty';
        }
        const mtu = this.parsePositiveInt(this.wgMtu);
        if (mtu < 0) {
            return 'MTU must be a positive integer';
        }
        if (mtu > TUN_INTERFACE_MTU) {
            return `MTU must not exceed ${TUN_INTERFACE_MTU}, the TUN interface MTU`;
        }
        if (this.parsePositiveInt(this.wgKeepalive) < 0) {
            return 'Keepalive interval must be a positive integer';
        }
        const routes = this.parseRoutes(this.wgRoutes);
        if (routes.length === 0) {
            return 'At least one route (CIDR) is required';
        }
        for (const route of routes) {
            if (parseCidr(route) === undefined) {
                return `Invalid CIDR: ${route}`;
            }
        }
        return undefined;
    }

    private async showFormError(message: string): Promise<void> {
        await this.getUIContext()
            .getPromptAction()
            .showDialog({ message: message })
            .catch(() => {
                Logger.Error(TAG, `show dialog failed!`);
            });
    }

    private notifySaved(): void {
        this.getUIContext()
            .getPromptAction()
            .showToast({ message: 'WireGuard settings saved' });
    }

    private async doSave(): Promise<void> {
        const failure = this.getValidationFailure();
        if (failure !== undefined) {
            Logger.Error(TAG, `refusing to save: ${failure}`);
            await this.showFormError(failure);
            return;
        }

        const wg = new WireGuardSettings();
        wg.privateKey = this.wgPrivateKey.trim();
        wg.peerPublicKey = this.wgPeerPublicKey.trim();
        wg.peerEndpoint = this.wgPeerEndpoint.trim();
        wg.localIp = this.wgLocalIp.trim();
        wg.mtu = this.parsePositiveInt(this.wgMtu);
        wg.keepaliveInterval = this.parsePositiveInt(this.wgKeepalive);
        wg.routes = this.parseRoutes(this.wgRoutes);

        const saved = await ConfigManager.saveWireGuardSettings(wg);
        if (!saved) {
            await this.showFormError('Failed to write settings.json, the changes were not kept');
            return;
        }
        Logger.Info(TAG, `wireguard settings saved, ${wg.routes.length} route(s)`);
        this.loadFromManager();
        this.notifySaved();
    }

    build() {
        Scroll() {
            Column({ space: 16 }) {
                Text('WireGuard')
                    .fontSize(24)
                    .fontWeight(FontWeight.Bold)

                Text('Feeds the "wg-outbound" generated for every VPN session, effective on next start.')
                    .fontSize(13)
                    .fontColor($r('sys.color.font_tertiary'))

                Row({ space: 8 }) {
                    Text('Private key')
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: 'base64 wireguard private key', text: this.wgPrivateKey!! })
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text('Peer public key')
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: 'base64 peer public key', text: this.wgPeerPublicKey!! })
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text('Peer endpoint')
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: 'host:port', text: this.wgPeerEndpoint!! })
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text('Local IP')
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: 'address of this device', text: this.wgLocalIp!! })
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text('MTU')
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: '1420', text: this.wgMtu!! })
                        .type(InputType.Number)
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text('Keepalive (s)')
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: '25', text: this.wgKeepalive!! })
                        .type(InputType.Number)
                        .layoutWeight(1)
                }

                Column({ space: 4 }) {
                    Text('Routes / Allowed IPs')
                    TextArea({ placeholder: 'one CIDR per line, e.g. 100.64.0.0/10', text: this.wgRoutes!! })
                        .height(140)
                        .width('100%')
                }
                .width('100%')

                Row({ space: 16 }) {
                    Button('Save')
                        .onClick(async () => {
                            await this.doSave();
                        })
                    Button('Reload')
                        .onClick(() => {
                            this.loadFromManager();
                        })
                }
            }
            .alignItems(HorizontalAlign.Start)
            .width('100%')
            .padding(16)
        }
        .width('100%')
        .height('100%')
    }
}
