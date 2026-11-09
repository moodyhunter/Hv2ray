// SPDX-License-Identifier: GPL-3.0-or-later

interface Statistics {
    directUp: number;
    directDown: number;
    proxyUp: number;
    proxyDown: number;
}

type StatisticsEventCallback = (stats: Statistics) => void;

/**
 * Start the VCore service.
 */
declare const startVCore: (config: string, statsPort: number, directTag: string, proxyTag: string) => void;

/**
 * Stop the VCore service.
 */
declare const stopVCore: () => void;

/**
 * Register a callback function to receive statistics.
 */
declare const onStatisticsEvent: (callback: StatisticsEventCallback) => void;

export { startVCore, stopVCore, onStatisticsEvent };
