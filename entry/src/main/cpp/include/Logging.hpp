#pragma once

#define LOG_DOMAIN 0xABCD

#ifndef LOG_TAG
#error "LOG_TAG must be defined"
#endif

#include <hilog/log.h>

#define LogError(fmt, ...) OH_LOG_Print(LogType::LOG_APP, LogLevel::LOG_ERROR, LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__)
#define LogWarn(fmt, ...)  OH_LOG_Print(LogType::LOG_APP, LogLevel::LOG_WARN, LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__)
#define LogInfo(fmt, ...)  OH_LOG_Print(LogType::LOG_APP, LogLevel::LOG_INFO, LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__)
#define LogDebug(fmt, ...) OH_LOG_Print(LogType::LOG_APP, LogLevel::LOG_DEBUG, LOG_DOMAIN, LOG_TAG, fmt, ##__VA_ARGS__)
