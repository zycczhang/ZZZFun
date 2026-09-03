param(
    [string]$BuildName = "1.0.0"
)

$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $projectRoot

$buildTime = Get-Date
$timestamp = $buildTime.ToString("yyyyMMdd-HHmmss")
$versionCode = ([DateTimeOffset]$buildTime).ToUnixTimeSeconds()
$versionName = "$BuildName-$timestamp"
$releaseDirectory = Join-Path $projectRoot "build\releases"
$sourceApk = Join-Path $projectRoot "build\app\outputs\flutter-apk\app-release.apk"
$targetApk = Join-Path $releaseDirectory "zzzfun-release-$timestamp.apk"

if ($versionCode -gt 2147483647) {
    throw "versionCode 超出 Android 允许的最大值。"
}

New-Item -ItemType Directory -Path $releaseDirectory -Force | Out-Null

Write-Host "Release versionName: $versionName"
Write-Host "Release versionCode: $versionCode"

flutter build apk --release --build-name $versionName --build-number $versionCode

if (-not (Test-Path -LiteralPath $sourceApk)) {
    throw "没有找到构建产物: $sourceApk"
}

Copy-Item -LiteralPath $sourceApk -Destination $targetApk -Force
Write-Host "APK: $targetApk"
