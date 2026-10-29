<#
.SYNOPSIS
    Re-vendors the Kazumi rule parsing layer from Predidit/Kazumi.

.DESCRIPTION
    Downloads the rule-engine sources from upstream and overwrites the copies
    in packages/kazumi_rules/lib/, then applies the two mechanical patches
    described in packages/kazumi_rules/UPSTREAM.md.

    Everything else is copied byte-for-byte, so a re-run is a plain overwrite:
    no merge conflicts, no manual editing.

.PARAMETER Ref
    Upstream git ref to sync from. Defaults to the last synced commit pin in
    packages/kazumi_rules/UPSTREAM.md when -UsePinned is passed, otherwise
    'main'.

.PARAMETER UsePinned
    Sync from the exact commit recorded in UPSTREAM.md instead of 'main'.

.EXAMPLE
    powershell -File tool/sync_kazumi_rules.ps1
    powershell -File tool/sync_kazumi_rules.ps1 -Ref v2.4.2
#>
[CmdletBinding()]
param(
    [string]$Ref = 'main',
    [switch]$UsePinned
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$destRoot = Join-Path $repoRoot 'packages/kazumi_rules'
$libRoot = Join-Path $destRoot 'lib'
$upstreamFile = Join-Path $destRoot 'UPSTREAM.md'
$rawBase = 'https://raw.githubusercontent.com/Predidit/Kazumi'
$apiBase = 'https://api.github.com/repos/Predidit/Kazumi'

# Files that make up the reusable parsing layer. Paths are relative to the
# upstream lib/ directory and are preserved verbatim under packages/kazumi_rules/lib/.
$files = @(
    'plugins/api_rule_config.dart'
    'plugins/anti_crawler_config.dart'
    'modules/roads/road_module.dart'
    'modules/search/plugin_search_module.dart'
    'utils/episode_url.dart'
    'services/plugin/api_rule_strategy.dart'
    'services/plugin/xpath_rule_strategy.dart'
    'services/plugin/rule_engine_models.dart'
)

# Upstream files that are deliberately NOT vendored, because they depend on
# Dio, Dio cookies, MobX, Hive or the app logger:
#   plugins/plugins.dart, services/plugin/rule_engine.dart,
#   services/plugin/plugin_cookie_manager.dart,
#   services/plugin/api_rule_engine.dart (a barrel file for the above).
# ZZZFun supplies equivalents in lib/models/kazumi_rule_models.dart and
# lib/services/kazumi_api_rule_engine.dart.

if ($UsePinned) {
    if (-not (Test-Path $upstreamFile)) {
        throw "Cannot use -UsePinned: $upstreamFile does not exist."
    }
    $pinnedMatch = Select-String -Path $upstreamFile -Pattern '^commit:\s*([0-9a-f]{40})' |
        Select-Object -First 1
    if (-not $pinnedMatch) {
        throw "Cannot use -UsePinned: no 'commit: <sha>' line found in UPSTREAM.md."
    }
    $Ref = $pinnedMatch.Matches[0].Groups[1].Value
    Write-Host "Syncing from pinned commit $Ref"
}

function Get-RemoteText {
    param([string]$Uri)
    $response = Invoke-WebRequest -Uri $Uri -UseBasicParsing -TimeoutSec 60 `
        -Headers @{ 'User-Agent' = 'ZZZFun-sync' }
    if ($response.StatusCode -ne 200) {
        throw "HTTP $($response.StatusCode) for $Uri"
    }
    return [System.Text.Encoding]::UTF8.GetString($response.RawContentStream.ToArray())
}

Write-Host "Resolving upstream commit for '$Ref'..."
$commitInfo = Invoke-RestMethod -Uri "$apiBase/commits/$Ref" -UseBasicParsing `
    -Headers @{ 'User-Agent' = 'ZZZFun-sync' }
$commitSha = $commitInfo.sha
Write-Host "Upstream commit: $commitSha"

$downloaded = @{}
foreach ($file in $files) {
    $url = "$rawBase/$commitSha/lib/$file"
    Write-Host "  fetching lib/$file"
    $downloaded[$file] = Get-RemoteText -Uri $url
}

# --- Patch 1: import prefix ------------------------------------------------
# The vendored package is named kazumi_rules, so upstream's internal
# 'package:kazumi/' imports must point at it.
foreach ($file in $downloaded.Keys) {
    $downloaded[$file] = $downloaded[$file].Replace('package:kazumi/', 'package:kazumi_rules/')
}

# --- Patch 2: drop the dio dependency --------------------------------------
# rule_engine_models.dart only imports dio to declare a CancelToken typedef.
# The request executor that actually uses dio is replaced by ZZZFun's own
# adapter (lib/services/kazumi_rule_engine.dart), so the typedef is dead here.
$modelsKey = 'services/plugin/rule_engine_models.dart'
if (-not $downloaded.ContainsKey($modelsKey)) {
    throw "Expected patch target '$modelsKey' was not downloaded."
}
$models = $downloaded[$modelsKey]
$before = $models
$models = $models -replace "(?m)^import 'package:dio/dio\.dart';\r?\n", ''
$models = $models -replace "(?m)^typedef RuleCancelToken = CancelToken;\r?\n", ''
if ($models -eq $before) {
    throw "Patch 2 no longer applies to $modelsKey - upstream changed. Review tool/sync_kazumi_rules.ps1."
}
$downloaded[$modelsKey] = $models

# --- Guard: API level ------------------------------------------------------
# The supported level is mirrored in lib/models/kazumi_rule_models.dart because
# api_endpoints.dart is not vendored. Fail loudly instead of silently rejecting
# every new rule.
Write-Host "Checking upstream rule API level..."
$endpointsUrl = "$rawBase/$commitSha/lib/request/config/api_endpoints.dart"
$endpoints = Get-RemoteText -Uri $endpointsUrl
$levelMatch = [regex]::Match($endpoints, 'static\s+const\s+int\s+apiLevel\s*=\s*(\d+)')
if (-not $levelMatch.Success) {
    throw 'Could not read apiLevel from upstream api_endpoints.dart - update tool/sync_kazumi_rules.ps1.'
}
$upstreamApiLevel = [int]$levelMatch.Groups[1].Value
$localModelFile = Join-Path $repoRoot 'lib/models/kazumi_rule_models.dart'
$localLevelMatch = [regex]::Match(
    (Get-Content -Raw -Path $localModelFile),
    'supportedApiLevel\s*=\s*(\d+)')
if (-not $localLevelMatch.Success) {
    throw "Could not read supportedApiLevel from $localModelFile."
}
$localApiLevel = [int]$localLevelMatch.Groups[1].Value
if ($upstreamApiLevel -ne $localApiLevel) {
    throw @"
API level mismatch: upstream is $upstreamApiLevel, ZZZFun declares $localApiLevel.

The vendored parsers were just updated, so update
lib/models/kazumi_rule_models.dart (KazumiRule.supportedApiLevel = $upstreamApiLevel)
to match, then re-run the tests.
"@
}
Write-Host "  apiLevel $upstreamApiLevel matches lib/models/kazumi_rule_models.dart"

$utf8NoBom = New-Object System.Text.UTF8Encoding $false
$written = 0
foreach ($file in $downloaded.Keys) {
    $target = Join-Path $libRoot $file.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
    $parent = Split-Path -Parent $target
    if (-not (Test-Path $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    $content = $downloaded[$file] -replace "`r`n", "`n"
    [System.IO.File]::WriteAllText($target, $content, $utf8NoBom)
    $written++
}
Write-Host "Wrote $written file(s) under packages/kazumi_rules/lib/"

$syncedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
$upstream = @"
# Vendored upstream

Source: https://github.com/Predidit/Kazumi (GPL-3.0)
commit: $commitSha
ref: $Ref
synced: $syncedAt

Files under `lib/` are copied verbatim except for the two patches below, which
`tool/sync_kazumi_rules.ps1` applies on every run. Do not edit them by hand -
re-run the script instead.

1. ``package:kazumi/`` imports are rewritten to ``package:kazumi_rules/``.
2. ``services/plugin/rule_engine_models.dart``: the ``package:dio`` import and
   the ``RuleCancelToken`` typedef are removed. The dio-based request executor
   is not vendored; ZZZFun supplies its own in
   ``lib/services/kazumi_rule_engine.dart``.

## Re-syncing after an upstream change

    powershell -File tool/sync_kazumi_rules.ps1

Then run the test suite. ``test/kazumi_rule_contract_test.dart`` fetches the
live KazumiRules catalog and fails when a published rule no longer parses.
"@
[System.IO.File]::WriteAllText($upstreamFile, ($upstream -replace "`r`n", "`n"), $utf8NoBom)
Write-Host "Updated packages/kazumi_rules/UPSTREAM.md"
