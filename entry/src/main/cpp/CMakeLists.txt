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

macro(add_component NAME TYPE ABBREV AFILE)
  add_library(${NAME} ${TYPE} IMPORTED)
  set_target_properties(${NAME} PROPERTIES INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_CURRENT_LIST_DIR}/core)
  set_target_properties(${NAME} PROPERTIES IMPORTED_LOCATION ${CMAKE_CURRENT_LIST_DIR}/core/${AFILE})
  add_library(${ABBREV} ALIAS ${NAME})
 if ("${TYPE}" STREQUAL "SHARED")
   file(COPY_FILE core/${AFILE} ${CMAKE_SOURCE_DIR}/../../../libs/arm64-v8a/${AFILE})
   set_target_properties(${NAME} PROPERTIES IMPORTED_SONAME ${AFILE})
 endif()
endmacro()

add_component(Hv2rayCore STATIC Hv2ray::Core libHvCore.a)
add_component(Hv2rayStats SHARED Hv2ray::Stats libHvStats.so)

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
    # Hv2ray::Stats
    ${CMAKE_CURRENT_LIST_DIR}/core/libHvStats.so
)

target_link_options(native PRIVATE)