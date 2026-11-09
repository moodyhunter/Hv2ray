#pragma once

#include "NapiCallbackStorage.hpp"
#include "Utils.hpp"

#include <optional>
#include <string>
#include <thread>

struct Statistics : public NapiObject
{
    size_t proxyUp;
    size_t proxyDown;

    size_t directUp;
    size_t directDown;

    explicit Statistics(size_t proxyUp, size_t proxyDown, size_t directUp, size_t directDown)
        : proxyUp(proxyUp), proxyDown(proxyDown), directUp(directUp), directDown(directDown)
    {
    }

    napi_value ToNapiValue(napi_env env) const override
    {
        napi_value obj;
        VERIFY_ERR_NULL(napi_create_object(env, &obj), "Failedtocreateobject");

        napi_value proxyUp, proxyDown, directUp, directDown;
        VERIFY_ERR_NULL(napi_create_int64(env, this->proxyUp, &proxyUp), "Failed to create tx");
        VERIFY_ERR_NULL(napi_create_int64(env, this->proxyDown, &proxyDown), "Failed to create rx");
        VERIFY_ERR_NULL(napi_create_int64(env, this->directUp, &directUp), "Failed to create tx");
        VERIFY_ERR_NULL(napi_create_int64(env, this->directDown, &directDown), "Failed to create rx");

        VERIFY_ERR_NULL(napi_set_named_property(env, obj, "proxyUp", proxyUp), "Failed to set tx");
        VERIFY_ERR_NULL(napi_set_named_property(env, obj, "proxyDown", proxyDown), "Failed to set rx");
        VERIFY_ERR_NULL(napi_set_named_property(env, obj, "directUp", directUp), "Failed to set tx");
        VERIFY_ERR_NULL(napi_set_named_property(env, obj, "directDown", directDown), "Failed to set rx");
        return obj;
    }
};

struct StartVCoreParams
{
    const std::string configuration;
    const std::string proxyTag;
    const std::string directTag;
    const long statsPort;
};

class VCoreManager : public Singleton<VCoreManager>
{
  public:
    std::optional<std::string> StartVCore(const StartVCoreParams &params);
    void StopVCore();
    void RegisterStatisticsCallback(napi_env env, napi_value callback);

  private:
    void EmitStatistics(size_t proxyUp, size_t proxyDown, size_t directUp, size_t directDown) const;

    void DoTerminateStatsWorker();

  private:
    std::thread statsWorker;
    NapiCallbackStorage<Statistics> g_callbackContexts;
};
