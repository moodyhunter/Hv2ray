#!/usr/bin/bash

# Set the environment variables for the development environment
this_dir=$(dirname "$(realpath $0)")

# get ARCH, TARGET and GOBINARY from env.ini
get_env() {
    name=$1

    file=$this_dir/env.ini
    if [ ! -f $file ]; then
        echo "Error: env.ini not found" >&2
        exit 1
    fi

    value=$(grep $name $this_dir/env.ini | cut -d'=' -f2)
    if [ -z $value ]; then
        echo "Error: $name is not set in env.ini" >&2
        exit 1
    fi
    echo $value
}

OHOS_NATIVE_HOME=$(get_env OHOS_NATIVE_HOME)
ARCH=$(get_env ARCH)
TARGET=$(get_env TARGET)
export GOBINARY=$(get_env GOBINARY)

LLVM="$OHOS_NATIVE_HOME/llvm"

export CC="$LLVM/bin/clang"
export CXX="$LLVM/bin/clang++"
export LD="$LLVM/bin/clang"
export AR="$LLVM/bin/llvm-ar"
export CGO_AR="$LLVM/bin/llvm-ar"
export GOASM="$LLVM/bin/llvm-as"

export GOOS="linux"
export GOARCH=$ARCH
export GOARM=""
export CGO_ENABLED="1"
export CGO_CFLAGS="-D__MUSL__ -Werror --target=$TARGET --sysroot=$OHOS_NATIVE_HOME/sysroot -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -fno-addrsig -Wa,--noexecstack -fPIC"
export CGO_CXXFLAGS=$env:CGO_CFLAGS
export CGO_LDFLAGS="--target=$TARGET -extar=$AR"

echo "Hv2rayCore Environment Configured"
