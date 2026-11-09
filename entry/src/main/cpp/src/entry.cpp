#define LOG_TAG "Hv2rayNativeEntry"

#include "Logging.hpp"
#include "NapiUtils.hpp"
#include "VCoreManager.hpp"

#include <node_api.h>

static napi_value NAPI_Global_onStatisticsEvent(napi_env env, napi_callback_info info)
{
    const auto input = NapiArgs<napi_function>::Get(env, info);
    if (!input.has_value())
        return nullptr;

    const auto [callback] = input.value();
    VCoreManager::Instance().RegisterStatisticsCallback(env, callback);
    return nullptr;
}

static napi_value NAPI_Global_startVCore(napi_env env, napi_callback_info info)
{
    const auto input = NapiArgs<napi_string, napi_number, napi_string, napi_string>::Get(env, info);
    if (!input.has_value())
        return nullptr;

    const auto [config, statsPort, directTag, proxyTag] = *input;
    const StartVCoreParams params = {
        .configuration = config,
        .proxyTag = proxyTag,
        .directTag = directTag,
        .statsPort = statsPort,
    };
    const auto err = VCoreManager::Instance().StartVCore(params);
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
        // startVCore: () => void
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
