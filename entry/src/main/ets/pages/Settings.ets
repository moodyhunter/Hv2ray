import Logger from '../utils/Logging';
import { Utils } from '../utils/Common';
import { ConfigManager } from '../core/config/ConfigManager';
import { parseCidr, WireGuardSettings } from '../core/config/WgSettings';
import { TUN_INTERFACE_MTU } from '../core/config/Generation';

const TAG = "Hv2ray-Settings"
const LABEL_WIDTH = 160;

interface WgFormFailure {
    reason: string;
    message: ResourceStr;
}

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

    private formatText(name: Resource, arg: string | number): string {
        try {
            return this.getUIContext()
                .getHostContext()!
                .resourceManager
                .getStringSync(name.id, arg);
        } catch (error) {
            Logger.Error(TAG, `failed to format resource ${name.id}: ${JSON.stringify(error)}`);
            return 'validation failed';
        }
    }

    /**
     * Returns the reason why the form cannot be saved, or undefined when
     * every field looks usable.
     */
    private getValidationFailure(): WgFormFailure | undefined {
        if (this.wgPrivateKey.trim().length === 0) {
            return { reason: 'private_key_empty', message: $r('app.string.err_wg_private_key') };
        }
        if (this.wgPeerPublicKey.trim().length === 0) {
            return { reason: 'peer_public_key_empty', message: $r('app.string.err_wg_peer_public_key') };
        }
        if (this.wgPeerEndpoint.trim().length === 0) {
            return { reason: 'peer_endpoint_empty', message: $r('app.string.err_wg_peer_endpoint') };
        }
        if (this.wgLocalIp.trim().length === 0) {
            return { reason: 'local_ip_empty', message: $r('app.string.err_wg_local_ip') };
        }
        const mtu = this.parsePositiveInt(this.wgMtu);
        if (mtu < 0) {
            return { reason: 'mtu_not_positive', message: $r('app.string.err_wg_mtu_positive') };
        }
        if (mtu > TUN_INTERFACE_MTU) {
            return {
                reason: 'mtu_too_large',
                message: this.formatText($r('app.string.err_wg_mtu_max'), TUN_INTERFACE_MTU)
            };
        }
        if (this.parsePositiveInt(this.wgKeepalive) < 0) {
            return { reason: 'keepalive_not_positive', message: $r('app.string.err_wg_keepalive') };
        }
        const routes = this.parseRoutes(this.wgRoutes);
        if (routes.length === 0) {
            return { reason: 'no_routes', message: $r('app.string.err_wg_routes_required') };
        }
        for (const route of routes) {
            if (parseCidr(route) === undefined) {
                return {
                    reason: 'invalid_cidr',
                    message: this.formatText($r('app.string.err_wg_cidr_invalid'), route)
                };
            }
        }
        return undefined;
    }

    private async showFormError(message: ResourceStr): Promise<void> {
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
            .showToast({ message: $r('app.string.msg_wg_saved') });
    }

    private async doSave(): Promise<void> {
        const failure = this.getValidationFailure();
        if (failure !== undefined) {
            Logger.Error(TAG, `refusing to save: ${failure.reason}`);
            await this.showFormError(failure.message);
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
            await this.showFormError($r('app.string.msg_wg_save_failed'));
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

                Text($r('app.string.wg_note'))
                    .fontSize(13)
                    .fontColor($r('sys.color.font_tertiary'))

                Row({ space: 8 }) {
                    Text($r('app.string.wg_private_key'))
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: $r('app.string.wg_private_key_hint'), text: this.wgPrivateKey!! })
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text($r('app.string.wg_peer_public_key'))
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: $r('app.string.wg_peer_public_key_hint'), text: this.wgPeerPublicKey!! })
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text($r('app.string.wg_peer_endpoint'))
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: 'host:port', text: this.wgPeerEndpoint!! })
                        .layoutWeight(1)
                }

                Row({ space: 8 }) {
                    Text($r('app.string.wg_local_ip'))
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: $r('app.string.wg_local_ip_hint'), text: this.wgLocalIp!! })
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
                    Text($r('app.string.wg_keepalive'))
                        .width(LABEL_WIDTH)
                    TextInput({ placeholder: '25', text: this.wgKeepalive!! })
                        .type(InputType.Number)
                        .layoutWeight(1)
                }

                Column({ space: 4 }) {
                    Text($r('app.string.wg_routes'))
                    TextArea({ placeholder: $r('app.string.wg_routes_hint'), text: this.wgRoutes!! })
                        .height(140)
                        .width('100%')
                }
                .width('100%')

                Row({ space: 16 }) {
                    Button($r('app.string.btn_save'))
                        .onClick(async () => {
                            await this.doSave();
                        })
                    Button($r('app.string.btn_reload'))
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
