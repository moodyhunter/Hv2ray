// SPDX-License-Identifier: GPL-3.0-or-later

#pragma once

#include <js_native_api.h>
#include <js_native_api_types.h>
#include <node_api.h>
#include <node_api_types.h>
#include <string_view>
#include <type_traits>

struct NapiObject
{
  public:
    NapiObject() = default;
    virtual ~NapiObject() = default;
    virtual napi_value ToNapiValue(napi_env env) const = 0;
};

template<typename TArg>
requires(std::is_base_of_v<NapiObject, TArg>) class NapiCallback
{
  public:
    explicit NapiCallback(napi_env e, std::string_view name, napi_value jsCallback) : env(e)
    {
        napi_value workName;
        napi_create_string_utf8(env, name.data(), NAPI_AUTO_LENGTH, &workName);
        napi_create_threadsafe_function(env, nullptr, nullptr, workName, 0, 1, nullptr, nullptr, nullptr, JsInvoker, &tsFn);
        napi_create_reference(env, jsCallback, 1, &callbackRef);
    }

    ~NapiCallback()
    {
        napi_delete_reference(env, callbackRef);
    }

    void Invoke(const TArg *arg) const
    {
        const auto argContext = new CallbackArg();
        argContext->callbackRef = callbackRef;
        argContext->arg = arg;
        napi_acquire_threadsafe_function(tsFn);
        napi_call_threadsafe_function(tsFn, argContext, napi_tsfn_nonblocking);
        napi_release_threadsafe_function(tsFn, napi_tsfn_release);
    }

  private:
    struct CallbackArg
    {
        napi_ref callbackRef = nullptr;
        const TArg *arg = nullptr;
    };

    static void JsInvoker(napi_env env, napi_value js_callBack, void *context, void *data)
    {
        (void) context;
        auto *const argContext = reinterpret_cast<CallbackArg *>(data);
        napi_get_reference_value(env, argContext->callbackRef, &js_callBack);
        const auto arg = argContext->arg->ToNapiValue(env);
        napi_call_function(env, nullptr, js_callBack, 1, &arg, nullptr);
        delete argContext;
    }

  private:
    napi_env env = nullptr;
    napi_ref callbackRef = nullptr;
    napi_threadsafe_function tsFn = nullptr;
};
