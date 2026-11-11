/**
 * Home 这一族页面（Home / HomeListRow / HomeDetail / HomeEditSheet）共用的东西：
 * 列表的派生视图类型、行与分组的尺寸、行菜单参数、以及两边都要用到的内核停止操作。
 * 不给其它页面用；其它页面的共用件在 PageCommon.ets。
 */
import { vpnExtension } from '@kit.NetworkKit';
import { BUNDLE_NAME } from 'BuildProfile';
import { Connection } from '../../core/config/Connection';
import { VCoreManager } from '../../vpn/VCoreManager';
import Logger from '../../utils/Logging';

const TAG = 'Hv2ray-HomePage';

/**
 * 行高与组头高度显式固定；HdsListItemCard 的 cardHeight 用同一个值。
 * cardWidth 不要给百分比，见 HomeListRow 里的说明。
 */
export const ROW_HEIGHT = 48;
export const GROUP_HEADER_HEIGHT = 40;

/** 卡片间距：组内 4vp，组之间 6vp。分组不再用 CARD 样式，所以这两个值就是全部的间隔 */
export const GROUP_ITEM_SPACING = 4;
export const GROUP_SECTION_SPACING = 6;

/**
 * 菜单模态化：点非菜单区域时不再穿透触发下层 ListItem 的点击。
 * mask 在 2in1 上不生效（系统配置不显示菜单蒙层），所以真正起作用的是 modalMode；
 * 两者都给，手机/平板上有蒙层，2in1 上靠 modalMode 拦住穿透。
 */
export const HOME_MENU_OPTIONS: MenuOptions = {
    modalMode: ModalMode.TARGET_WINDOW,
    mask: true,
};

/** 列表渲染用的派生视图，不持久化，只由 ConfigManager 的数据推导 */
export interface HomeConnectionRow {
    connection: Connection;
    groupId: string;
}

export interface HomeGroupRow {
    id: string;
    name: string;
    connections: HomeConnectionRow[];
}

export interface HomeGroupOption {
    id: string;
    name: string;
}

export async function stopKernel(): Promise<void> {
    VCoreManager.StopVCore();
    try {
        await vpnExtension.stopVpnExtensionAbility({
            bundleName: BUNDLE_NAME,
            abilityName: 'VpnAbility',
        });
    } catch (error) {
        Logger.Error(TAG, `failed to stop VpnAbility: ${JSON.stringify(error)}`);
    }
}
