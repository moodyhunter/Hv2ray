#define LOG_TAG "Hv2rayCore"

#include "VCoreManager.hpp"

#include "Logging.hpp"
#include "libHvCore.h"
#include "libHvStats.h"

#include <cstdlib>
#include <thread>

static bool stopStats = false;

using namespace std::chrono_literals;

extern "C" [[maybe_unused, gnu::used]] void cgo_log(const char *component, const char *msg)
{
    LogWarn("%{public}s: %{public}s", component, msg);
    free((void *) component);
    free((void *) msg);
}

extern "C" [[maybe_unused, gnu::used]] void DoWriteAccessLog(const char *from, const char *to, const char *outbound, bool accepted)
{
    LogWarn("%{public}s --> %{public}s; via %{public}s, %{public}s", from, to, outbound, accepted ? "accepted" : "rejected");
    free((void *) from);
    free((void *) to);
    free((void *) outbound);
}

extern "C" [[maybe_unused, gnu::used]] void DoWriteGeneralLog(HvLogSeverity severity, const char *content)
{
    if (severity <= HvLogSeverity::Severity_Warning)
    {
        LogWarn("%{public}d ::: %{public}s", severity, content);
    }
    free((void *) content);
}

std::optional<std::string> VCoreManager::StartVCore(const StartVCoreParams &params)
{
    LogInfo("VCoreManager::StartVCore");
    setenv("V2RAY_LOCATION_ASSET", "/", 1);
    const char *errmsg = StartV2RayKernel((char *) params.configuration.c_str());
    if (errmsg != nullptr)
    {
        LogError("StartKernel failed: %{public}s", errmsg);
        std::string errmsg_str(errmsg);
        free((void *) errmsg);
        return errmsg_str;
    }

    DoTerminateStatsWorker();

    stopStats = false;
    statsWorker = std::thread(
        [localParams = params, this]()
        {
            std::this_thread::sleep_for(1s);
            LogInfo("stats thread started: %{public}lu", localParams.statsPort);

            HvStatsConfig config = {
                .statsPort = static_cast<int>(localParams.statsPort),
                .directTag = localParams.directTag.c_str(),
                .proxyTag = localParams.proxyTag.c_str(),
            };

            std::string resultStr;
            {
                const auto result = InitStats(&config); // const safe
                resultStr = result;
                free(result);
            }
            if (!resultStr.empty())
            {
                LogWarn("stats thread failed: %{public}s", resultStr.c_str());
                CloseStats();
                return;
            }

            while (!stopStats)
            {
                const auto stats = GetStats();
                this->EmitStatistics(stats.proxyUpload, stats.proxyDownload, stats.directUpload, stats.directDownload);
                std::this_thread::sleep_for(1s);
            }

            CloseStats();
        });
    return std::nullopt;
}

void VCoreManager::StopVCore()
{
    LogInfo("VCoreManager::StopVCore()");
    DoTerminateStatsWorker();
    CloseV2RayKernel();
}

void VCoreManager::RegisterStatisticsCallback(napi_env env, napi_value callback)
{
    LogInfo("TunManager::RegisterStatisticsCallback");
    g_callbackContexts.Clear();
    g_callbackContexts.AddCallback(env, "StatisticsCallback", callback);
}

void VCoreManager::EmitStatistics(size_t proxyUp, size_t proxyDown, size_t directUp, size_t directDown) const
{
    const auto newStats = new Statistics(proxyUp, proxyDown, directUp, directDown);
    g_callbackContexts.InvokeAll(newStats);
}

void VCoreManager::DoTerminateStatsWorker()
{
    stopStats = true;
    if (statsWorker.joinable())
        statsWorker.join();
}