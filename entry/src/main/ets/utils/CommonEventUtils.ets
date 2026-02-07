import { Constants, KernelEvent, KernelEventType, Stat } from "./Common";
import Logger from "./Logging";
import { BUNDLE_NAME } from 'BuildProfile';
import { commonEventManager } from "@kit.BasicServicesKit";

const TAG = 'utils/CommonEventUtil';

class CommonEventUtilsImpl {
    constructor() {
        Logger.Info(TAG, `constructor`);
    }

    public async subscribeStatsEvent(callback: (stat: Stat) => void): Promise<void> {
        await this.doSubscribeStatsEvent(Constants.STATS_EVENT_NAME, (data: string) => {
            callback(JSON.parse(data) as Stat);
        })
    }

    public async subscribeKernelEvent(callback: (stat: KernelEvent) => void): Promise<void> {
        await this.doSubscribeStatsEvent(Constants.KERNEL_EVENT_NAME, (data: string) => {
            callback(JSON.parse(data) as KernelEvent);
        })
    }

    private async doSubscribeStatsEvent(eventName: string, callback: Callback<string>) {
        let subscriber = commonEventManager.createSubscriberSync({
            events: [eventName],
            publisherBundleName: BUNDLE_NAME,
        });

        try {
            await commonEventManager.subscribeToEvent(subscriber, (event: commonEventManager.CommonEventData) => {
                Logger.Debug(TAG, `Received common event: ${JSON.stringify(event)}`);
                callback(event.data ?? '');
            });
        } catch (error) {
            Logger.Error(TAG, `failed to subscribe: ${JSON.stringify(error)}`);
        }
    }

    public publishStatsEvent(stat: Stat) {
        this.doPublishEvent(Constants.STATS_EVENT_NAME, JSON.stringify(stat));
    }

    public publishKernelErrorEvent(eventType: KernelEventType, errorMessages?: string[]) {
        let kernelEvent: KernelEvent = {
            type: eventType,
            message: errorMessages ?? [],
        }
        this.doPublishEvent(Constants.KERNEL_EVENT_NAME, JSON.stringify(kernelEvent));
    }

    private doPublishEvent(eventId: string, eventData: string) {
        let options: commonEventManager.CommonEventPublishData = {
            bundleName: BUNDLE_NAME,
            data: eventData,
        };

        commonEventManager.publish(eventId, options, (err, _data) => {
            if (err && err.code) {
                Logger.Error(TAG, `Failed to publish event: ${JSON.stringify(err)}`);
                return;
            }
        });
    }
}

export const CommonEventUtils = new CommonEventUtilsImpl();