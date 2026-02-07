// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include "Logging.hpp"
#include "NapiCallback.hpp"

#include <js_native_api_types.h>
#include <list>
#include <string_view>

template<typename TArg>
struct NapiCallbackStorage
{
  public:
    explicit NapiCallbackStorage() = default;

    void AddCallback(napi_env env, std::string_view name, napi_value jsCallback)
    {
        const auto callback = std::make_shared<NapiCallback<TArg>>(env, name, jsCallback);
        callbacks.push_back(callback);
    }

    void InvokeAll(const TArg *arg) const
    {
        for (const auto &callback : callbacks)
        {
            callback->Invoke(arg);
        }
    }

    void Clear()
    {
        callbacks.clear();
    }

  private:
    std::list<std::shared_ptr<NapiCallback<TArg>>> callbacks;
};
