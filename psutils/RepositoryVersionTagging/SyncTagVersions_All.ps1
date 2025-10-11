
# Copyright © Igor Grešovnik.
# Part of IGLib: https://github.com/ajgorhoe/IGLib.modules.IGLibScripts
# License:
# https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/LICENSE.md
# Doc: https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/psutils/RepositoryVersionTagging/README_VersionTaggingToolkit.md

<#
.SYNOPSIS
  Wrapper that calls SyncTagVersions.ps1 with a merged repo list.

.DESCRIPTION
  - Hard-codes a base list of repositories in $InitialRepoDirs.
  - Merges $InitialRepoDirs with any -RepoDirs passed to this wrapper.
  - Passes through all other parameters unchanged to SyncTagVersions.ps1.
  - Runs from the script's directory and restores the original location.

.PARAMETER RepoDirs
  Optional additional repository roots (absolute or relative to this script).

.PARAMETER Branch
  Target branch (default 'main'). Sync script may fall back to 'master' per-repo.

.PARAMETER Pull
  If set, the sync script will fetch tags and fast-forward pull before computing versions.

.PARAMETER BumpMajor
.PARAMETER BumpMinor
.PARAMETER BumpPatch
  If set (and corresponding -Increment* is 0), bumps that version part by 1.

.PARAMETER IncrementMajor
.PARAMETER IncrementMinor
.PARAMETER IncrementPatch
  Integer amounts to bump; override the corresponding -Bump* switches if > 0.

.PARAMETER PreReleaseLabel
  Optional prerelease label applied AFTER a bump/increment (X.Y.Z-<label>.1).

.PARAMETER DryRun
  If set, performs all operations except actually creating or pushing tags.

.EXAMPLE
  .\RunSyncTagVersions.ps1
  # Uses only the hard-coded $InitialRepoDirs.

.EXAMPLE
  .\RunSyncTagVersions.ps1 -RepoDirs ..\ExtraRepo -Pull -BumpPatch
  # Merges hard-coded repos with ..\ExtraRepo, pulls before computing, bumps patch.

#>

[CmdletBinding()]
param(
  [string[]] $RepoDirs = @(),

  [string] $Branch = 'main',
  [switch] $Pull,

  [switch] $BumpMajor,
  [switch] $BumpMinor,
  [switch] $BumpPatch,

  [int] $IncrementMajor = 0,
  [int] $IncrementMinor = 0,
  [int] $IncrementPatch = 0,

  [string] $PreReleaseLabel,

  [switch] $DryRun
)

Write-Host "`n`n=== RunSyncTagVersions.ps1 ===`n" -ForegroundColor Cyan
Write-Host "This script merges a base set of repos with any passed via -RepoDirs," -ForegroundColor Cyan
Write-Host "  then calls SyncTagVersions.ps1 with all parameters." -ForegroundColor Cyan

if ($RepoDirs -and $RepoDirs.Count -gt 0) {
  Write-Host ("Additional RepoDirs passed: `n{0}" -f ($RepoDirs -join ", `n")) -ForegroundColor Cyan
} else {
  Write-Host "No additional RepoDirs passed (null  or empty array)." -ForegroundColor Cyan
}


# ---------------- Configurable parameters: ----------------
# Relative paths are resolved against THIS script's directory.

$RelativeSyncScriptPath = "./SyncTagVersions.ps1"  # relative to this script

$InitialRepoDirs = @(
  # IGLib Core repositories:
  "../../IGLibCore",
  "../../IGLibGraphics3D",
  "../../IGLibScripting",
  "../../IGLibScriptingCs",
  "../../IGLibSandbox",
  "../../IGLibScripts",
  "../../IGLibEventAggregator",
  # IGLib Framework repositories (legacy):
  "../../iglib",
  "../../iglibexternal",
  "../../igsolutions",
  "../../shelldev",
  "../../unittests",
  "../../igsandbox",
  "../../iglibapp"
)

[bool] $IsDryRun = $DryRun.IsPresent

# Write-Host "`nNote: This wrapper currently forces -DryRun for safety; remove line below to allow real changes.`n" -ForegroundColor Yellow 
# $IsDryRun = $true  # FORCE dry-run (overrides parameter); remove to allow real changes

# The base set of repos to always include:

# ----------------------------------------------------------------------

# Resolves a path to canonical absolute form (rooted, full, no trailing slash)
function Resolve-CanonicalPath {
  param([string]$PathText)
  if ([string]::IsNullOrWhiteSpace($PathText)) { return $PathText }
  if ([IO.Path]::IsPathRooted($PathText)) {
    $p = $PathText
  } else {
    $p = Join-Path -Path $PSScriptRoot -ChildPath $PathText
  }
  $sep = [IO.Path]::DirectorySeparatorChar
  $p = $p -replace '[\\/]', [string]$sep
  $full = [IO.Path]::GetFullPath($p)
  if ($full.Length -gt 3) { $full = $full.TrimEnd($sep) }
  return $full
}

# Merges two string arrays of paths, de-duplicating (case-insensitive) on 
# canonical absolute path
function Merge-RepoDirs {
  param([string[]]$Base, [string[]]$Extra)

  $list = New-Object System.Collections.Generic.List[string]
  foreach ($x in @($Base)) {
    if (-not [string]::IsNullOrWhiteSpace($x)) { $list.Add($x) }
  }
  foreach ($x in @($Extra)) {
    if (-not [string]::IsNullOrWhiteSpace($x)) { $list.Add($x) }
  }
  # De-duplicate while preserving first-seen order (compare on canonical absolute path)
  $seen = New-Object System.Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
  $merged = New-Object System.Collections.Generic.List[string]
  $mergedCanonical = New-Object System.Collections.Generic.List[string]
  foreach ($x in $list) {
    $canon = Resolve-CanonicalPath $x
    if (-not $seen.Contains($canon)) {
      $null = $seen.Add($canon)
      # Keep original expression for user-facing echo:
      $merged.Add($x)
      # Keep canonical paths for sync script because the script does its own 
      # path resolution of relative paths, possibly with a different base dir:
      $mergedCanonical.Add($canon)
      # Write-Host "Added to merged: $x"
      # Write-Host "Added to mergedCanonical: $canon"
    }
  }
  $retMerged = $merged.ToArray()
  $retMergedCanonical = $mergedCanonical.ToArray()
  return $retMerged, $retMergedCanonical
}

# Build merged RepoDirs
($MergedRepoDirs, $MergedRepoDirsCanonical) = Merge-RepoDirs -Base $InitialRepoDirs -Extra $RepoDirs
if (-not $MergedRepoDirs -or $MergedRepoDirs.Count -eq 0) {
  Write-Host "No repositories specified or configured. Nothing to do." -ForegroundColor Yellow
  return
}

# Locate the script for syncing version tags
$syncPath = Join-Path -Path $PSScriptRoot -ChildPath "$RelativeSyncScriptPath"
Write-Host ("`nScript path: {0}`n" -f $syncPath) -ForegroundColor Cyan

if (-not (Test-Path -LiteralPath $syncPath)) {
  Write-Host "Version tag synchronization script not found at:`n    $syncPath" -ForegroundColor Red
  return
}

if ($IsDryRun) {
  Write-Host "`n*** DRY RUN MODE: No tags will be created or pushed. ***`n" -ForegroundColor Yellow
}

# Echo parameters
Write-Host "=== RunSyncTagVersions parameters ===" -ForegroundColor Cyan
Write-Host ("Repos (merged): `n  {0}" -f ($MergedRepoDirs -join ",`n  "))
Write-Host ("Repos (merged, canonical): `n  {0}" -f ($MergedRepoDirsCanonical -join ",`n  "))
Write-Host ("Branch: {0}" -f $Branch)
Write-Host ("Pull: {0}" -f ($Pull.IsPresent))
Write-Host ("Increments -> Major:{0} Minor:{1} Patch:{2}" -f $IncrementMajor, $IncrementMinor, $IncrementPatch)
Write-Host ("Bumps -> Major:{0} Minor:{1} Patch:{2}" -f ($BumpMajor.IsPresent), ($BumpMinor.IsPresent), ($BumpPatch.IsPresent))
if ([string]::IsNullOrWhiteSpace($PreReleaseLabel)) {
  Write-Host "PreReleaseLabel: <none>"
} else {
  Write-Host ("PreReleaseLabel: {0}" -f $PreReleaseLabel)
}
Write-Host ("IsDryrun: {0} " -f $IsDryRun)
Write-Host "=====================================" -ForegroundColor Cyan

# Splat params to the sync script
$params = @{
  RepoDirs        = $MergedRepoDirsCanonical
  Branch          = $Branch
  Pull            = $Pull.IsPresent
  BumpMajor       = $BumpMajor.IsPresent
  BumpMinor       = $BumpMinor.IsPresent
  BumpPatch       = $BumpPatch.IsPresent
  IncrementMajor  = $IncrementMajor
  IncrementMinor  = $IncrementMinor
  IncrementPatch  = $IncrementPatch
  PreReleaseLabel = $PreReleaseLabel
  DryRun          = $IsDryRun
}

# Run SyncTagVersions.ps1 from this directory; restore caller location afterward
$orig = Get-Location
try {
  Set-Location -LiteralPath $PSScriptRoot
  
  Write-Host "`nCalling ${RelativeSyncScriptPath}...`n" -ForegroundColor Cyan 
  & $syncPath @params
}
finally {
  Set-Location $orig
}
