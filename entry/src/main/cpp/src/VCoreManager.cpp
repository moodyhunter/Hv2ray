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

std::optional<std::string> VCoreManager::StartVCore(const std::string &config)
{
    LogInfo("VCoreManager::StartVCore");
    const char *errmsg = StartV2RayKernel((char *) config.c_str());
    if (errmsg != nullptr)
    {
        LogError("StartKernel failed: %{public}s", errmsg);
        std::string errmsg_str(errmsg);
        free((void *) errmsg);
        return errmsg_str;
    }

    stopStats = false;

    std::thread t(
        []()
        {
            std::this_thread::sleep_for(5s);
            LogInfo("stats thread started");

            const auto result = Dial("127.0.0.1:8080");
            LogWarn("stats thread: %{public}s", result);
            while (!stopStats)
            {
                const auto stats = GetStats("outbound>>>proxy-global-82>>>traffic>>>downlink");
                const auto directstats = GetStats("outbound>>>direct>>>traffic>>>downlink");
                LogInfo("stats: direct: %{public}lld, proxy: %{public}lld", directstats / 1000, stats / 1000);
                std::this_thread::sleep_for(1s);
            }
        });

    t.detach();
    return std::nullopt;
}

void VCoreManager::StopVCore()
{
    stopStats = true;
    LogInfo("VCoreManager::StopVCore()");
    CloseV2RayKernel();
}
