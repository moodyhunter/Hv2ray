#pragma once

template<class T>
struct Singleton
{
    static T &Instance()
    {
        static T instance;
        return instance;
    }

  protected:
    explicit Singleton() = default;
};

// clang-format off
#define VERIFY_ERR(expr, msg) if ((expr) != napi_ok) { OH_LOG_ERROR(LogType::LOG_APP, msg); return; }
#define VERIFY_ERR_NULL(expr, msg) if ((expr) != napi_ok) { OH_LOG_ERROR(LogType::LOG_APP, msg); return nullptr; }
// clang-format on
