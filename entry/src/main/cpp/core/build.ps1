# Description: Build script for Hv2rayCore

function Test-Environment {
    $requiredEnvVars = @("CC", "CXX", "LD", "AR", "CGO_AR", "GOASM", "GOOS", "GOARCH", "CGO_ENABLED", "CGO_CFLAGS", "CGO_CXXFLAGS", "CGO_LDFLAGS")
    foreach ($envVar in $requiredEnvVars) {
        if (-not (Test-Path env:$envVar)) {
            # check if the environment variable is set
            Write-Host "Variable $envVar is not set: ${env:$envVar}"
            exit 1
        }
    }
}

Test-Environment

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$outputFile = "libHv2rayCore.a"

# if GOBINARY is set, use it as the go binary, otherwise use "go"
if ($null -eq $env:GOBINARY) {
    $env:GOBINARY = "go"
}
else {
    Write-Host "Using custom go binary: $env:GOBINARY"
}

Push-Location $scriptDir
& $env:GOBINARY build -tlsmodegd -trimpath -ldflags="-s -w" -buildmode c-archive -v -o $outputFile "core.go" "cgo.go"
Pop-Location

# check return code
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to build $sourceFile"
    exit $LASTEXITCODE
}
