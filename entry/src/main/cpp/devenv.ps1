# Description: Build script for Hv2rayCore

$envData = Get-Content .\env.ini | ConvertFrom-StringData

$OHOS_NATIVE_HOME = $envData.OHOS_NATIVE_HOME
$ARCH = $envData.ARCH
$TARGET = $envData.TARGET
$env:GOBINARY = $envData.GOBINARY

if ($null -eq $OHOS_NATIVE_HOME) {
    Write-Host "OHOS_NATIVE_HOME is not set, please set it to the root of the OpenHarmony SDK"
    return
}

$LLVM = "$OHOS_NATIVE_HOME/llvm"

$env:CC = "$LLVM/bin/clang"
$env:CXX = "$LLVM/bin/clang++"
$env:LD = "$LLVM/bin/clang"
$env:AR = "$LLVM/bin/llvm-ar"
$env:CGO_AR = "$LLVM/bin/llvm-ar"
$env:GOASM = "$LLVM/bin/llvm-as"

$env:GOOS = "linux"
$env:GOARCH = $ARCH
$env:GOARM = "";
$env:CGO_ENABLED = "1"
$env:CGO_CFLAGS = "-D__MUSL__ -Werror --target=$TARGET --sysroot=$OHOS_NATIVE_HOME/sysroot -fdata-sections -ffunction-sections -funwind-tables -fstack-protector-strong -no-canonical-prefixes -fno-addrsig -Wa,--noexecstack -fPIC"
$env:CGO_CXXFLAGS = $env:CGO_CFLAGS
$env:CGO_LDFLAGS = "--target=$TARGET -extar=$AR"

Write-Host "Hv2rayCore Environment Configured"
