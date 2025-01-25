# SPDX-License-Identifier: GPL-3.0-or-later

cmake_minimum_required(VERSION 3.10.0)
project(Hv2ray)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(NATIVERENDER_ROOT_PATH ${CMAKE_CURRENT_SOURCE_DIR})

if(DEFINED PACKAGE_FIND_FILE)
    include(${PACKAGE_FIND_FILE})
endif()

message(STATUS "Configuring for architecture: ${OHOS_ARCH}")
add_subdirectory(hev-socks5-tunnel)

add_library(libHv2rayCore STATIC IMPORTED)
set_target_properties(libHv2rayCore PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_LIST_DIR}/core/libHv2rayCore.a)
set_target_properties(libHv2rayCore PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_CURRENT_LIST_DIR}/core)
add_library(Hv2ray::Core ALIAS libHv2rayCore)

add_library(native SHARED
    src/entry.cpp
    src/VCoreManager.cpp
    src/TunManager.cpp
)

target_compile_options(native PRIVATE -Wall -Wextra -pedantic)
target_compile_options(native PRIVATE -Wno-variadic-macros -Wno-gnu-zero-variadic-macro-arguments)
target_include_directories(native
    PRIVATE
    ${CMAKE_CURRENT_LIST_DIR}/include
    ${NATIVERENDER_ROOT_PATH}
    ${NATIVERENDER_ROOT_PATH}/include
)

target_link_libraries(native PRIVATE
    PUBLIC
    libace_napi.z.so
    libhilog_ndk.z.so
    libohpreferences.so

    HevSocks5Tunnel
    Hv2ray::Core
)
