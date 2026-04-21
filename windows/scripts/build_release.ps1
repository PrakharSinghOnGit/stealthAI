$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsRoot = Resolve-Path (Join-Path $scriptDir "..")

$buildDir = Join-Path $windowsRoot "build"
$distDir = Join-Path $windowsRoot "dist"
$sdkRoot = Join-Path $windowsRoot ".webview2sdk"
$sdkVersion = "1.0.2792.45"
$nugetZip = Join-Path $sdkRoot "webview2.zip"
$extractDir = Join-Path $sdkRoot "pkg"
$sdkDir = Join-Path $extractDir "build/native"

function Get-PeMachineType {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -lt 0x40) {
        throw "Invalid PE file: $Path"
    }

    $peOffset = [BitConverter]::ToInt32($bytes, 0x3C)
    if ($peOffset -lt 0 -or ($peOffset + 6) -ge $bytes.Length) {
        throw "Corrupt PE header in: $Path"
    }

    if ($bytes[$peOffset] -ne 0x50 -or $bytes[$peOffset + 1] -ne 0x45 -or $bytes[$peOffset + 2] -ne 0x00 -or $bytes[$peOffset + 3] -ne 0x00) {
        throw "Missing PE signature in: $Path"
    }

    return [BitConverter]::ToUInt16($bytes, $peOffset + 4)
}

if (Test-Path $buildDir) { Remove-Item -Recurse -Force $buildDir }
if (Test-Path $distDir) { Remove-Item -Recurse -Force $distDir }
if (Test-Path $sdkRoot) { Remove-Item -Recurse -Force $sdkRoot }

New-Item -ItemType Directory -Path $buildDir | Out-Null
New-Item -ItemType Directory -Path $distDir | Out-Null
New-Item -ItemType Directory -Path $sdkRoot | Out-Null

Write-Host "Downloading WebView2 SDK $sdkVersion..."
Invoke-WebRequest -Uri "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/$sdkVersion" -OutFile $nugetZip
Expand-Archive -Path $nugetZip -DestinationPath $extractDir -Force

if (!(Test-Path $sdkDir)) {
    throw "WebView2 SDK not found at $sdkDir"
}

Write-Host "Configuring CMake..."
cmake -S $windowsRoot -B $buildDir -G "Visual Studio 17 2022" -A x64 -DWEBVIEW2_SDK_DIR="$sdkDir"

Write-Host "Building Release..."
cmake --build $buildDir --config Release

$exePath = Join-Path $buildDir "Release/stealthAI.exe"
if (!(Test-Path $exePath)) {
    throw "Release executable not found at $exePath"
}

$machineType = Get-PeMachineType -Path $exePath
if ($machineType -ne 0x8664) {
    throw ("Expected AMD64 executable (0x8664), but found machine type 0x{0:X4}. Aborting package." -f $machineType)
}

$packageDir = Join-Path $distDir "stealthAI-windows-x64"
New-Item -ItemType Directory -Path $packageDir | Out-Null

Copy-Item $exePath (Join-Path $packageDir "stealthAI.exe")
Copy-Item (Join-Path $windowsRoot "README.md") (Join-Path $packageDir "README.md")

$zipPath = Join-Path $distDir "stealthAI-windows-x64.zip"
Compress-Archive -Path "$packageDir/*" -DestinationPath $zipPath -Force

Write-Host "Created release artifact: $zipPath"
