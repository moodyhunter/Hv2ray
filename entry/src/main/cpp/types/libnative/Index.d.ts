// SPDX-License-Identifier: GPL-3.0-or-later

interface Statistics {
  tx: number;
  rx: number;
}

/**
 * Start the TUN service.
 */
declare const startTun: (tunFd: number, socks5Port: number) => void;

/**
 * Stop the TUN service.
 */
declare const stopTun: () => void;

/**
 * Start the VCore service.
 */
declare const startVCore: (socks5Port: number, config: string) => void;

/**
 * Stop the VCore service.
 */
declare const stopVCore: () => void;

/**
 * Register a callback function to receive statistics.
 */
declare const onStatisticsEvent: (
  interval: number,
  callback: (stats: Statistics) => void
) => void;

/**
 * Intentionally not documented.
 */
declare const internalTest: (arg1: number) => number;

export { startTun, stopTun, startVCore, stopVCore, onStatisticsEvent, internalTest, };
