#include "Utils.hpp"

#include <mutex>
#include <node_api.h>
#include <thread>

struct Statistics
{
    size_t tx;
    size_t rx;
};

class TunManager : public Singleton<TunManager>
{
  public:
    void StartTun(long tunFd, int socks5Port);
    void StopTun();

    void RegisterStatisticsCallback(napi_env env, napi_value callback, int interval = 1);
    void EmitStatistics(const Statistics &stats) const;

  private:
    std::mutex mutex;
    std::thread stats_thread;
    std::thread tun_thread;
    std::atomic_bool running = false;
    int statsInterval = 1;

  private:
    napi_threadsafe_function tsf_stats;
};
