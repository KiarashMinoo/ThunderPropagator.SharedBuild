<#
.SYNOPSIS
    Bump every ThunderPropagator-family PackageVersion in a repo's Directory.Packages.props
    to the latest version published on nuget.org -- prerelease/beta included.

.DESCRIPTION
    Lives in ThunderPropagator.SharedBuild and is downloaded into every consuming repo's
    .shared-props\ folder by the same DownloadSharedProps target that fetches
    Shared.Build.props / Shared.Nuget.props / Shared.PackageIds.props / Shared.DependencyUpdater.props.
    A consuming repo may additionally keep a committed copy of this script at
    .github\scripts\ (so the check has no download/network dependency for the script
    itself -- Shared.DependencyUpdater.props prefers that copy when present). Path
    resolution below works unmodified from either location, or any other folder inside
    the repo, since it walks up to find Directory.Packages.props as the repo-root marker
    instead of assuming a fixed relative layout.

    Fully auto-discovering: it reads Shared.PackageIds.props to learn every
    "{Name}PackageId" pattern ThunderPropagator publishes, then scans the target repo's
    own Directory.Packages.props for PackageVersion entries whose Include is one of those
    PackageId properties. Entries that share the same version property (e.g.
    BuildingBlocksPackageId and BuildingBlocksModulesPackageId both pinned via
    BuildingBlocksVersion) are resolved and updated together; entries pinned with a
    literal version string are updated in place individually. Any repo that adopts the
    "$(XxxPackageId)" convention works with this script unmodified -- nothing here is
    specific to any one consuming repo.

    nuget.org is a public feed with no auth required, so no token or source registration
    is needed -- this queries "$Source" directly regardless of what's in NuGet.Config.

.PARAMETER PropsPath
    Path to the target repo's Directory.Packages.props. Defaults to the nearest
    Directory.Packages.props found by walking up from this script's own folder -- works
    whether this script lives in <repo>\.shared-props\, <repo>\.github\scripts\, or
    anywhere else inside the repo.

.PARAMETER SharedPackageIdsPath
    Path to Shared.PackageIds.props. Defaults to the copy sitting next to this script if
    present, otherwise <repo root>\.shared-props\Shared.PackageIds.props.

.PARAMETER Source
    NuGet v3 service index to search. Defaults to nuget.org.

.PARAMETER Check
    Print current vs. latest version for every discovered dependency and exit without writing.

.EXAMPLE
    pwsh .shared-props/Update-ThunderPropagatorDependencies.ps1
    pwsh .shared-props/Update-ThunderPropagatorDependencies.ps1 -Check
    pwsh .shared-props/Update-ThunderPropagatorDependencies.ps1 -WhatIf
    pwsh .shared-props/Update-ThunderPropagatorDependencies.ps1 -PropsPath ..\Directory.Packages.props
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $PropsPath            = "",
    [string] $SharedPackageIdsPath = "",
    [string] $Source               = "https://api.nuget.org/v3/index.json",
    [switch] $Check
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# ── Resolve paths (works from .shared-props\, .github\scripts\, or any other
#    folder inside the target repo -- walks up to find Directory.Packages.props as
#    the repo-root marker instead of assuming a fixed relative layout) ───────────

function Find-RepoRoot {
    param([string]$StartDirectory)
    $dir = $StartDirectory
    while ($dir) {
        if (Test-Path (Join-Path $dir "Directory.Packages.props")) { return $dir }
        $parent = Split-Path $dir -Parent
        if (-not $parent -or $parent -eq $dir) { return $null }
        $dir = $parent
    }
    return $null
}

if ([string]::IsNullOrWhiteSpace($PropsPath)) {
    $repoRoot = Find-RepoRoot -StartDirectory $PSScriptRoot
    if (-not $repoRoot) {
        throw "Could not locate Directory.Packages.props by walking up from '$PSScriptRoot'. Pass -PropsPath explicitly."
    }
    $PropsPath = Join-Path $repoRoot "Directory.Packages.props"
}
if (-not (Test-Path $PropsPath)) {
    throw "Directory.Packages.props not found at '$PropsPath'. Pass -PropsPath explicitly."
}

if ([string]::IsNullOrWhiteSpace($SharedPackageIdsPath)) {
    # Prefer a copy sitting right next to this script (the .shared-props\ case);
    # otherwise fall back to <repo root>\.shared-props\Shared.PackageIds.props
    # (the repo-local-copy case, e.g. .github\scripts\).
    $sibling              = Join-Path $PSScriptRoot "Shared.PackageIds.props"
    $SharedPackageIdsPath = if (Test-Path $sibling) { $sibling } else { Join-Path (Split-Path $PropsPath -Parent) ".shared-props/Shared.PackageIds.props" }
}
if (-not (Test-Path $SharedPackageIdsPath)) {
    throw "Shared.PackageIds.props not found at '$SharedPackageIdsPath'. Run 'dotnet restore' first, or pass -SharedPackageIdsPath."
}

# ── Helpers ───────────────────────────────────────────────────────────────────

function Write-Step { param($m) Write-Host "  -> $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "  OK $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "  !! $m" -ForegroundColor Yellow }

function Get-VersionSortKey {
    # SemanticVersion understands prerelease ordering (1.0.1-beta.9 < 1.0.1-beta.10 < 1.0.1).
    param([string]$Version)
    try { [System.Management.Automation.SemanticVersion]::Parse($Version) }
    catch { $null }
}

function Get-LatestPackageVersion {
    param([string]$PackageId, [string]$SourceUrl)

    $json = dotnet package search $PackageId --exact-match --prerelease --source $SourceUrl --format json 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $json) {
        Write-Warn "  '$PackageId': search failed (exit $LASTEXITCODE) -- skipping"
        return $null
    }

    $parsed = $json | ConvertFrom-Json -ErrorAction SilentlyContinue
    if (-not $parsed) {
        Write-Warn "  '$PackageId': could not parse search output -- skipping"
        return $null
    }

    $matched = $parsed.searchResult |
               ForEach-Object { $_.packages } |
               Where-Object { $_.id -ieq $PackageId }

    if (-not $matched) {
        Write-Warn "  '$PackageId': not found on '$SourceUrl' -- skipping"
        return $null
    }

    # --exact-match changes the search-result shape: an unqualified search returns one
    # summary entry per package with a "latestVersion" field, but --exact-match instead
    # returns one entry PER PUBLISHED VERSION, each carrying a "version" field (no
    # "latestVersion" at all). Accept either shape -- via PSObject.Properties so a
    # missing property returns $null instead of throwing under Set-StrictMode -- and
    # take the highest version across every entry returned.
    $versions = foreach ($pkg in $matched) {
        $prop = $pkg.PSObject.Properties['latestVersion']
        if (-not $prop) { $prop = $pkg.PSObject.Properties['version'] }
        if ($prop) { $prop.Value }
    }

    if (-not $versions) {
        Write-Warn "  '$PackageId': search result had neither 'latestVersion' nor 'version' -- skipping"
        return $null
    }

    return $versions | Sort-Object { Get-VersionSortKey $_ } -Descending | Select-Object -First 1
}

# ── Step 1: learn every "{Name}PackageId" pattern from Shared.PackageIds.props ─
#    e.g. BuildingBlocksPackageId -> "ThunderPropagator.BuildingBlocks"
#    (literal text captured up to the first "$(...)" suffix token)

$sharedPackageIdsContent = Get-Content -Path $SharedPackageIdsPath -Raw
$packageIdMap            = @{}

foreach ($m in [regex]::Matches($sharedPackageIdsContent, '<(?<prop>\w+PackageId)>(?<lit>[^$<]+)')) {
    $packageIdMap[$m.Groups['prop'].Value] = $m.Groups['lit'].Value.Trim()
}

if ($packageIdMap.Count -eq 0) {
    throw "No '{Name}PackageId' properties found in '$SharedPackageIdsPath' -- nothing to discover."
}

# ── Step 2: scan the target repo's Directory.Packages.props for PackageVersion
#    entries whose Include references one of those PackageId properties ───────
#    Groups entries that share a version PROPERTY together (so BuildingBlocks +
#    BuildingBlocksModules resolve and update as one family); entries pinned
#    with a literal version string are tracked individually.

$propsContent = Get-Content -Path $PropsPath -Raw
$pattern      = '<PackageVersion\s+Include="\$\((?<propid>\w+PackageId)\)"\s+Version="(?:\$\((?<verprop>\w+)\)|(?<verlit>[^"$][^"]*))"'

$byVersionProperty = [ordered]@{}   # verprop -> list of literal package ids
$byLiteralEntry    = @()            # one entry per literally-pinned PackageVersion line

foreach ($m in [regex]::Matches($propsContent, $pattern)) {
    $propId = $m.Groups['propid'].Value
    if (-not $packageIdMap.ContainsKey($propId)) { continue }   # not a known ThunderPropagator package id
    $literalId = $packageIdMap[$propId]

    if ($m.Groups['verprop'].Success) {
        $verProp = $m.Groups['verprop'].Value
        if (-not $byVersionProperty.Contains($verProp)) { $byVersionProperty[$verProp] = @() }
        $byVersionProperty[$verProp] += $literalId
    } else {
        $byLiteralEntry += [pscustomobject]@{
            PropId     = $propId
            LiteralId  = $literalId
            Current    = $m.Groups['verlit'].Value
        }
    }
}

if ($byVersionProperty.Count -eq 0 -and $byLiteralEntry.Count -eq 0) {
    Write-Warn "No ThunderPropagator-family PackageVersion entries found in '$PropsPath' -- nothing to update."
    exit 0
}

# ── Banner ────────────────────────────────────────────────────────────────────
# nuget.org is public and needs no auth or source registration -- $Source is
# queried directly via "dotnet package search --source", independent of
# whatever sources are configured in this repo's own NuGet.Config.

Write-Host ""
Write-Host "ThunderPropagator Dependency Updater" -ForegroundColor White
Write-Host "  Props      : $PropsPath"
Write-Host "  PackageIds : $SharedPackageIdsPath"
Write-Host "  Source     : $Source"
Write-Host "  Mode       : $(if ($Check) { 'check only' } else { 'update' })"
Write-Host ""

# ── Resolve latest version per discovered dependency ──────────────────────────

$propertyUpdates = @()   # @{ Property; Old; New }
$literalUpdates  = @()   # @{ PropId; LiteralId; Old; New }

foreach ($verProp in $byVersionProperty.Keys) {
    $literalIds = $byVersionProperty[$verProp] | Select-Object -Unique
    Write-Step "Resolving '$verProp' from: $($literalIds -join ', ')"

    $candidates = foreach ($id in $literalIds) {
        $v = Get-LatestPackageVersion -PackageId $id -SourceUrl $Source
        if ($v) { [pscustomobject]@{ PackageId = $id; Version = $v } }
    }

    if (-not $candidates) {
        Write-Warn "  No versions resolved for '$verProp' -- leaving as-is."
        continue
    }

    $distinctVersions = $candidates.Version | Select-Object -Unique
    if ($distinctVersions.Count -gt 1) {
        Write-Warn "  '$verProp' package ids disagree on latest version: $($distinctVersions -join ', ') -- using the highest."
    }

    $latest = $candidates |
              Sort-Object { Get-VersionSortKey $_.Version } -Descending |
              Select-Object -First 1 -ExpandProperty Version

    $currentMatch = [regex]::Match($propsContent, "<$verProp>([^<]*)</$verProp>")
    $current      = if ($currentMatch.Success) { $currentMatch.Groups[1].Value } else { $null }

    if (-not $current) {
        Write-Warn "  Property '$verProp' not found as its own element in $PropsPath -- skipping."
        continue
    }

    if ($current -eq $latest) {
        Write-Ok "  $verProp is already latest: $current"
    } else {
        Write-Host "  $verProp : $current --> $latest" -ForegroundColor Yellow
        $propertyUpdates += [pscustomobject]@{ Property = $verProp; Old = $current; New = $latest }
    }
}

foreach ($entry in $byLiteralEntry) {
    Write-Step "Resolving literal-pinned '$($entry.LiteralId)'"
    $latest = Get-LatestPackageVersion -PackageId $entry.LiteralId -SourceUrl $Source
    if (-not $latest) { continue }

    if ($entry.Current -eq $latest) {
        Write-Ok "  $($entry.LiteralId) is already latest: $($entry.Current)"
    } else {
        Write-Host "  $($entry.LiteralId) : $($entry.Current) --> $latest" -ForegroundColor Yellow
        $literalUpdates += [pscustomobject]@{ PropId = $entry.PropId; LiteralId = $entry.LiteralId; Old = $entry.Current; New = $latest }
    }
}

$totalUpdates = $propertyUpdates.Count + $literalUpdates.Count

# ── Check mode: report only ───────────────────────────────────────────────────

Write-Host ""
if ($Check) {
    if ($totalUpdates -eq 0) {
        Write-Ok "All ThunderPropagator dependencies are already at the latest version."
    } else {
        Write-Warn "$totalUpdates update(s) available (run without -Check to apply)."
    }
    exit 0
}

if ($totalUpdates -eq 0) {
    Write-Ok "Nothing to update. $PropsPath is untouched."
    exit 0
}

# ── Apply updates ─────────────────────────────────────────────────────────────

foreach ($u in $propertyUpdates) {
    $propsContent = $propsContent -replace "<$($u.Property)>[^<]*</$($u.Property)>", "<$($u.Property)>$($u.New)</$($u.Property)>"
}

foreach ($u in $literalUpdates) {
    $linePattern = "(<PackageVersion\s+Include=`"\`$\($($u.PropId)\)`"\s+Version=`")[^`"]*(`")"
    # Single-quoted replacement so .NET regex -- not PowerShell -- interprets ${1}/${2} as backreferences.
    $replacement = '${1}' + $u.New + '${2}'
    $propsContent = $propsContent -replace $linePattern, $replacement
}

if ($PSCmdlet.ShouldProcess($PropsPath, "Write $totalUpdates updated version(s)")) {
    Set-Content -Path $PropsPath -Value $propsContent -NoNewline -Encoding UTF8
    Write-Ok "Wrote $totalUpdates update(s) to $PropsPath"
}

Write-Host ""
Write-Host "----------------------------------------------------" -ForegroundColor White
foreach ($u in $propertyUpdates) { Write-Host "  $($u.Property): $($u.Old) -> $($u.New)" -ForegroundColor Green }
foreach ($u in $literalUpdates)  { Write-Host "  $($u.LiteralId): $($u.Old) -> $($u.New)" -ForegroundColor Green }
Write-Host "----------------------------------------------------" -ForegroundColor White
Write-Host "  Run 'dotnet restore' to pull the updated package(s)." -ForegroundColor DarkGray
