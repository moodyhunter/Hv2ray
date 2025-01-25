#!/usr/bin/bash
# Description: Build script for Hv2rayCore

test_environment() {
    requiredEnvVars=("CC" "CXX" "LD" "AR" "CGO_AR" "GOASM" "GOOS" "GOARCH" "CGO_ENABLED" "CGO_CFLAGS" "CGO_CXXFLAGS" "CGO_LDFLAGS")
    for envVar in "${requiredEnvVars[@]}"; do
        if [ -z "${!envVar}" ]; then
            echo "Variable $envVar is not set: ${!envVar}" >&2
            exit 1
        fi
    done
}

test_environment

scriptdir=$(dirname "$(realpath $0)")
outputFile="libHv2rayCore.a"

if [ -z "$GOBINARY" ]; then
    GOBINARY="go"
else
    echo "Using custom go binary: $GOBINARY" >&2
fi

pushd $scriptdir
$GOBINARY build -tlsmodegd -trimpath -ldflags="-s -w" -buildmode c-archive -v -o $outputFile "core.go" "cgo.go"
popd

# check return code
if [ $? -ne 0 ]; then
    echo "Failed to build $sourceFile" >&2
    exit $?
fi
