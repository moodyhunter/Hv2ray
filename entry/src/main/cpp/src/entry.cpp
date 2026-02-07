#define LOG_TAG "Hv2rayNativeEntry"

#include "Logging.hpp"
#include "NapiUtils.hpp"
#include "TunManager.hpp"
#include "VCoreManager.hpp"

#include <node_api.h>
#include <stdio.h>
#include <unistd.h>

static napi_value NAPI_Global_startTun(napi_env env, napi_callback_info info)
{
    const auto input = NapiArgs<napi_number, napi_number>::Get(env, info);
    if (!input.has_value())
        return nullptr;

    const auto [tunFd, socksPort] = *input;
    TunManager::Instance().StartTun(tunFd, socksPort);

    return nullptr;
}

static napi_value NAPI_Global_stopTun(napi_env env, napi_callback_info info)
{
    const auto input = NapiArgs<>::Get(env, info);
    if (!input.has_value())
        return nullptr;

    TunManager::Instance().StopTun();

    return nullptr;
}

static napi_value NAPI_Global_onStatisticsEvent(napi_env env, napi_callback_info info)
{
    const auto input = NapiArgs<napi_number, napi_function>::Get(env, info);
    if (!input.has_value())
        return nullptr;

    const auto [interval, callback] = input.value();
    TunManager::Instance().RegisterStatisticsCallback(env, callback, interval);

    return nullptr;
}

static napi_value NAPI_Global_startVCore(napi_env env, napi_callback_info info)
{
    const auto input = NapiArgs<napi_number, napi_string>::Get(env, info);
    if (!input.has_value())
        return nullptr;

    const auto [socks5Port, config_string] = *input;
    const auto err = VCoreManager::Instance().StartVCore(config_string);

    int fds[2];
    const auto errc = pipe(fds);
    LogError("pipe error: %{public}d, [%{public}d, %{public}d]", errc, fds[0], fds[1]);
    close(fds[0]);
    close(fds[1]);

    if (err.has_value())
    {
        napi_throw_error(env, nullptr, err.value().c_str());
        return nullptr;
    }

    return nullptr;
}

static napi_value NAPI_Global_stopVCore(napi_env env, napi_callback_info info)
{
    const auto input = NapiArgs<>::Get(env, info);
    if (!input.has_value())
        return nullptr;

    VCoreManager::Instance().StopVCore();
    return nullptr;
}

static napi_value InitNativeModule(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        // onStatisticsEvent: (callback: (stats: Statistics) => void) => void
        { "onStatisticsEvent", nullptr, NAPI_Global_onStatisticsEvent, nullptr, nullptr, nullptr, napi_default, nullptr },
        // startTun: (tunFd: number) => void
        { "startTun", nullptr, NAPI_Global_startTun, nullptr, nullptr, nullptr, napi_default, nullptr },
        // stopTun: () => void
        { "stopTun", nullptr, NAPI_Global_stopTun, nullptr, nullptr, nullptr, napi_default, nullptr },
        // startVCore: (socks5Port: number) => void
        { "startVCore", nullptr, NAPI_Global_startVCore, nullptr, nullptr, nullptr, napi_default, nullptr },
        // stopVCore: () => void
        { "stopVCore", nullptr, NAPI_Global_stopVCore, nullptr, nullptr, nullptr, napi_default, nullptr },
    };

    const auto status = napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    if (status != napi_ok)
        LogError("Failed to define some properties");

    return exports;
}

static napi_module hv2rayModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = InitNativeModule,
    .nm_modname = "native",
    .nm_priv = nullptr,
    .reserved = { 0 },
};

[[maybe_unused, gnu::used]] __attribute__((constructor)) void RegisterEntryModule(void)
{
    napi_module_register(&hv2rayModule);
}
