#define LOG_TAG "Hv2rayTun"

#include "TunManager.hpp"

#include "Logging.hpp"
#include "hev-main.h"

#include <hilog/log.h>
#include <node_api.h>

using namespace std::chrono_literals;

static constexpr LogLevel convert_loglevel(HevLoggerLevel in)
{
    switch (in)
    {
        case HEV_LOGGER_DEBUG: return LogLevel::LOG_DEBUG;
        case HEV_LOGGER_INFO: return LogLevel::LOG_INFO;
        case HEV_LOGGER_WARN: return LogLevel::LOG_WARN;
        case HEV_LOGGER_ERROR: return LogLevel::LOG_ERROR;
        default: return LogLevel::LOG_INFO;
    }
}

static void do_logging_hev(HevLoggerLevel level, const char *fmt, va_list ap)
{
    if (level <= HEV_LOGGER_INFO)
        return; // we don't need debug log

    char buf[1024];
    vsnprintf(buf, sizeof(buf), fmt, ap);
    OH_LOG_Print(LogType::LOG_APP, convert_loglevel(level), LOG_DOMAIN, LOG_TAG, "%{public}s", buf);
}

Config hev_config = {
    .srv = { .user = nullptr, .pass = nullptr, .mark = 0, .udp_in_udp = true, .port = 0, .pipeline = 0, .addr = "127.0.0.1" },
    .logging = do_logging_hev,
};

void TunManager::StartTun(long tunFd, int socks5Port)
{
    if (running)
        return;

    [[maybe_unused]] std::lock_guard lock(this->mutex);
    static const auto tunnelWorker = [this](long arg)
    {
        running = true;
        hev_socks5_tunnel_main(arg);
    };

    static const auto statsWorker = [this]()
    {
        size_t last_tx, last_rx;
        hev_socks5_tunnel_stats(nullptr, &last_tx, nullptr, &last_rx);
        while (running)
        {
            std::this_thread::sleep_for(statsInterval * 1s);
            size_t tx, rx;
            hev_socks5_tunnel_stats(nullptr, &tx, nullptr, &rx);
            if (tx >= last_tx && rx >= last_rx)
            {
                const size_t speed_tx = (tx - last_tx) / statsInterval;
                const size_t speed_rx = (rx - last_rx) / statsInterval;
                last_tx = tx, last_rx = rx;
                EmitStatistics(speed_tx, speed_rx);
            }
            else
            {
                LogError("wrap detected");
                EmitStatistics(0, 0);
            }
        }
    };

    LogInfo("TunManager::StartTun(tunFd: %{public}ld, socks5Port: %{public}d)", tunFd, socks5Port);
    hev_config.srv.port = socks5Port;
    tun_thread = std::thread(tunnelWorker, tunFd);
    stats_thread = std::thread(statsWorker);
}

void TunManager::StopTun()
{
    [[maybe_unused]] std::lock_guard lock(this->mutex);
    running = false;
    hev_socks5_tunnel_quit();
    if (tun_thread.joinable())
        tun_thread.join();
    if (stats_thread.joinable())
        stats_thread.join();
}

void TunManager::RegisterStatisticsCallback(napi_env env, napi_value callback, int interval)
{
    LogInfo("TunManager::RegisterStatisticsCallback");
    g_callbackContexts.Clear();
    g_callbackContexts.AddCallback(env, "StatisticsCallback", callback);
    statsInterval = interval;
}

void TunManager::EmitStatistics(size_t tx, size_t rx) const
{
    const auto newStats = new Statistics(tx, rx);
    g_callbackContexts.InvokeAll(newStats);
}
