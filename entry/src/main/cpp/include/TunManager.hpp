#include "NapiCallbackStorage.hpp"
#include "Utils.hpp"

#include <mutex>
#include <node_api.h>
#include <thread>

struct Statistics : public NapiObject
{
    size_t tx;
    size_t rx;

    explicit Statistics(size_t tx, size_t rx) : tx(tx), rx(rx)
    {
    }

    napi_value ToNapiValue(napi_env env) const override
    {
        napi_value obj;
        VERIFY_ERR_NULL(napi_create_object(env, &obj), "Failedtocreateobject");

        napi_value tx, rx;
        VERIFY_ERR_NULL(napi_create_int64(env, this->tx, &tx), "Failed to create tx");
        VERIFY_ERR_NULL(napi_create_int64(env, this->rx, &rx), "Failed to create rx");

        VERIFY_ERR_NULL(napi_set_named_property(env, obj, "tx", tx), "Failed to set tx");
        VERIFY_ERR_NULL(napi_set_named_property(env, obj, "rx", rx), "Failed to set rx");
        return obj;
    }
};

class TunManager : public Singleton<TunManager>
{
  public:
    void StartTun(long tunFd, int socks5Port);
    void StopTun();

    void RegisterStatisticsCallback(napi_env env, napi_value callback, int interval = 1);
    void EmitStatistics(size_t tx, size_t rx) const;

  private:
    std::mutex mutex;
    std::thread stats_thread;
    std::thread tun_thread;
    std::atomic_bool running = false;
    int statsInterval = 1;

  private:
    NapiCallbackStorage<Statistics> g_callbackContexts;
};
