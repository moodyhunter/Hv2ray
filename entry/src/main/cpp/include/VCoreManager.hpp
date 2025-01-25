#pragma once

#include "Utils.hpp"

#include <optional>
#include <string>

class VCoreManager : public Singleton<VCoreManager>
{
  public:
    std::optional<std::string> StartVCore(const std::string &config);
    void StopVCore();
};
