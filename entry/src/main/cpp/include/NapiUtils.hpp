#pragma once

#include <array>
#include <node_api.h>
#include <optional>
#include <string>
#include <utility>

template<napi_valuetype t>
struct NapiValueConverter
{
    static constexpr napi_valuetype type = napi_undefined;
    void Get(napi_env, napi_value){};
};

#define DeclareNapiValueConverter(_type, _type_t, _convert_func)                                                                                                         \
    template<>                                                                                                                                                           \
    struct NapiValueConverter<_type>                                                                                                                                     \
    {                                                                                                                                                                    \
        using type_t = _type_t;                                                                                                                                          \
        using optional_t = std::optional<type_t>;                                                                                                                        \
        static constexpr napi_valuetype type = _type;                                                                                                                    \
        static optional_t Get(napi_env env, napi_value value)                                                                                                            \
        {                                                                                                                                                                \
            type_t ret;                                                                                                                                                  \
            napi_valuetype arg_type = napi_undefined;                                                                                                                    \
            napi_typeof(env, value, &arg_type);                                                                                                                          \
            if (arg_type != _type)                                                                                                                                       \
                return std::nullopt;                                                                                                                                     \
            _convert_func(env, value, &ret);                                                                                                                             \
            return ret;                                                                                                                                                  \
        }                                                                                                                                                                \
    }

DeclareNapiValueConverter(napi_number, long, napi_get_value_int64);
DeclareNapiValueConverter(napi_boolean, bool, napi_get_value_bool);
DeclareNapiValueConverter(napi_string, std::string,
                          [](napi_env env, napi_value value, std::string *ret)
                          {
                              size_t len = 0;
                              napi_get_value_string_utf8(env, value, nullptr, 0, &len);
                              ret->resize(len, '\0');
                              napi_get_value_string_utf8(env, value, ret->data(), len + 1, &len);
                          });
DeclareNapiValueConverter(napi_function, napi_value, [](napi_env, napi_value value, napi_value *ret) { *ret = value; });
DeclareNapiValueConverter(napi_object, napi_value, [](napi_env, napi_value value, napi_value *ret) { *ret = value; });

template<napi_valuetype... types>
struct NapiArgs
{
    static constexpr auto NTypes = sizeof...(types);
    using Result = std::tuple<typename NapiValueConverter<types>::type_t...>;
    using OptionalResult = std::tuple<std::optional<typename NapiValueConverter<types>::type_t>...>;
    using NapiValueArray = std::array<napi_value, NTypes>;

    template<class S = std::make_index_sequence<NTypes>>
    struct DoConvert; // doesn't need to be defined

    template<size_t... Is>
    struct DoConvert<std::index_sequence<Is...>>
    {
        static OptionalResult impl(napi_env env, NapiValueArray args)
        {
            return std::make_tuple(NapiValueConverter<types>::Get(env, args[Is])...);
        }
    };

    static std::optional<Result> Get(napi_env env, napi_callback_info info)
    {
        NapiValueArray args;
        size_t argc = NTypes;
        napi_get_cb_info(env, info, &argc, args.data(), nullptr, nullptr);

        if (argc != NTypes)
        {
            napi_throw_type_error(env, nullptr, "Wrong number of arguments");
            return {};
        }

        const auto optional_result = DoConvert<>::impl(env, args);
        const bool is_all_valid = std::apply([](const auto &...args) { return (... && args.has_value()); }, optional_result);
        if (!is_all_valid)
        {
            napi_throw_type_error(env, nullptr, "Wrong arguments");
            return {};
        }

        const auto result = std::apply([](const auto &...args) { return std::make_tuple(args.value()...); }, optional_result);
        return std::make_optional(result);
    }
};
