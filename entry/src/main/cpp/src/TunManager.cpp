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
    if (level == HEV_LOGGER_DEBUG)
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
            const size_t speed_tx = (tx - last_tx) / statsInterval, speed_rx = (rx - last_rx) / statsInterval;
            last_tx = tx, last_rx = rx;
            EmitStatistics(Statistics{ speed_tx, speed_rx });
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

    if (tsf_stats)
    {
        LogInfo("TunManager::RegisterStatisticsCallback: release old tsf_stats");
        napi_release_threadsafe_function(tsf_stats, napi_tsfn_release);
    }

    napi_value resource_name;
    napi_create_string_utf8(env, "stats", NAPI_AUTO_LENGTH, &resource_name);
    napi_create_threadsafe_function(
        env, callback, nullptr, resource_name, 0, 1, nullptr, nullptr, nullptr,
        [](napi_env env, napi_value js_callback, void *context, void *data)
        {
            (void) context;

            napi_value undefined;
            VERIFY_ERR(napi_get_undefined(env, &undefined), "Failed to get undefined");

            // create object from tsf_stats
            napi_value obj;
            {
                Statistics tsf_stats = *(Statistics *) data;
                VERIFY_ERR(napi_create_object(env, &obj), "Failed to create object");

                napi_value tx, rx;
                VERIFY_ERR(napi_create_int64(env, tsf_stats.tx, &tx), "Failed to create tx");
                VERIFY_ERR(napi_create_int64(env, tsf_stats.rx, &rx), "Failed to create rx");

                VERIFY_ERR(napi_set_named_property(env, obj, "tx", tx), "Failed to set tx");
                VERIFY_ERR(napi_set_named_property(env, obj, "rx", rx), "Failed to set rx");
            }

            VERIFY_ERR(napi_call_function(env, undefined, js_callback, 1, &obj, nullptr), "Failed to call JS callback");
        },
        &tsf_stats);

    statsInterval = interval;
}

void TunManager::EmitStatistics(const Statistics &stats) const
{
    napi_call_threadsafe_function(tsf_stats, (void *) &stats, napi_tsfn_blocking);
}
