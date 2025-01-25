#define LOG_TAG "Hv2rayCore"

#include "VCoreManager.hpp"

#include "Logging.hpp"
#include "libHv2rayCore.h"

[[maybe_unused, gnu::used]] void hv2ray_kernel_log(const char *msg)
{
    LogWarn("GoLog %{public}s", msg);
}

std::optional<std::string> VCoreManager::StartVCore(const std::string &config)
{
    LogInfo("VCoreManager::StartVCore(config: %s)", config.c_str());
    const char *errmsg = StartV2RayKernel((char *) config.c_str());
    if (errmsg != nullptr)
    {
        LogError("StartKernel failed: %{public}s", errmsg);
        std::string errmsg_str(errmsg);
        free((void *) errmsg);
        return errmsg_str;
    }

    return std::nullopt;
}

void VCoreManager::StopVCore()
{
    LogInfo("VCoreManager::StopVCore()");
    CloseV2RayKernel();
}
