import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';

class Hv2rayPreferences {
    private static pref?: preferences.Preferences = undefined;

    private static EnsurePreference(context: Context, name: string): preferences.Preferences {
        if (!Hv2rayPreferences.pref) {
            Hv2rayPreferences.pref = preferences.getPreferencesSync(context, { name: name });
        }
        return Hv2rayPreferences.pref;
    }

    static GetSocks5Port(context: Context): number {
        const pref = Hv2rayPreferences.EnsurePreference(context, "core");
        let value = pref.getSync("socks5.port", 51081);
        return value as number;
    }

    static GetConfig(context: Context): string {
        const pref = Hv2rayPreferences.EnsurePreference(context, "core");
        let value = pref.getSync("config", "");
        return value as string;
    }

    static SetConfig(context: Context, config: string) {
        const pref = Hv2rayPreferences.EnsurePreference(context, "core");
        pref.putSync("config", config);
        pref.flush();
    }
}

export default Hv2rayPreferences;
