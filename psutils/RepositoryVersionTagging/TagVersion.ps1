
# Copyright © Igor Grešovnik.
# Part of IGLib: https://github.com/ajgorhoe/IGLib.modules.IGLibScripts
# License:
# https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/LICENSE.md
# Doc: https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/psutils/RepositoryVersionTagging/README_VersionTaggingToolkit.md

<#
.SYNOPSIS
  Tags a branch (default: main) with a version computed by GitVersion, optionally
  bumping major/minor/patch by 1 or by an arbitrary amount, and optionally
  re-applying a prerelease label after a bump.

.DESCRIPTION
  - If -Directory is omitted, the script runs in its own folder and only requires
    that folder to be inside a Git repo (not necessarily the repo root).
  - If -Directory is provided, that directory must be the repo root.
  - Optionally pulls latest changes before calculating version (-Pull).
  - Supports -Branch to tag a branch other than 'main'.
  - Supports bump switches (-BumpMajor/-BumpMinor/-BumpPatch) to bump by 1.
  - Supports increment integers (-IncrementMajor/-IncrementMinor/-IncrementPatch) to bump
    by an arbitrary amount; these override the switches if > 0.
  - If a bump occurs and -PreReleaseLabel is supplied, the tag becomes X.Y.Z-<label>.1.
  - Restores the original working directory AND the originally checked-out branch
    (if the script switched branches), even on error.

.PARAMETER Directory
  Optional path to the repository root (absolute or relative to the script file).
  If provided, it MUST be the repository root.

.PARAMETER Branch
  The branch to tag. Defaults to 'main'.

.PARAMETER Pull
  If specified, fetches tags and pulls latest changes (fast-forward only) before tagging.

.PARAMETER BumpMajor
  If specified (and corresponding -IncrementMajor is 0), bumps MAJOR by 1 (resets minor/patch to 0).

.PARAMETER BumpMinor
  If specified (and corresponding -IncrementMinor is 0), bumps MINOR by 1 (resets patch to 0).

.PARAMETER BumpPatch
  If specified (and corresponding -IncrementPatch is 0), bumps PATCH by 1.

.PARAMETER IncrementMajor
  Integer (default 0). If > 0, bumps MAJOR by that amount (resets minor/patch to 0).
  Overrides -BumpMajor.

.PARAMETER IncrementMinor
  Integer (default 0). If > 0, bumps MINOR by that amount (resets patch to 0).
  Overrides -BumpMinor.

.PARAMETER IncrementPatch
  Integer (default 0). If > 0, bumps PATCH by that amount.
  Overrides -BumpPatch.

.PARAMETER PreReleaseLabel
  Optional prerelease label to apply **after** a bump (e.g., 'beta', 'rc', 'dev', 'feature.x').
  Resulting tag is `X.Y.Z-<label>.1`. Must match `[0-9A-Za-z\-\.]+`.
  Ignored if no bump occurs (in that case we tag with GitVersion's FullSemVer as-is).

.EXAMPLE
  .\TagVersion.ps1 -BumpPatch
  # From 2.0.44[-something], tags v2.0.45 (stable)

.EXAMPLE
  .\TagVersion.ps1 -BumpMinor -PreReleaseLabel rc
  # From 2.0.44[-something], tags v2.1.0-rc.1

.EXAMPLE
  .\TagVersion.ps1 -IncrementMinor 2 -PreReleaseLabel feature.widgets
  # From 2.0.44[-something], tags v2.2.0-feature.widgets.1
#>

[CmdletBinding()]
param(
  [string] $Directory,
  [string] $Branch = 'main',
  [switch] $Pull,
  [switch] $BumpMajor,
  [switch] $BumpMinor,
  [switch] $BumpPatch,
  [int] $IncrementMajor = 0,
  [int] $IncrementMinor = 0,
  [int] $IncrementPatch = 0,
  [string] $PreReleaseLabel
)

# We don't want Write-Error to stop the script, but we want to see errors;
# use default ('Continue'):
$ErrorActionPreference = 'Continue' # Never stop; handle errors manually


# Writes a red message; if -Throw switch is on, also throws exception 
# with this message.
function Write-ErrorReport {
    param([string]$Message, [switch]$Throw)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    if ($Throw) {
        throw $Message
    }
}

function Resolve-TargetDirectory {
  param([string]$Dir)
  if ([string]::IsNullOrWhiteSpace($Dir)) { return $PSScriptRoot }
  if ([System.IO.Path]::IsPathRooted($Dir)) {
    return (Resolve-Path -LiteralPath $Dir).ProviderPath
  } else {
    $combined = Join-Path -Path $PSScriptRoot -ChildPath $Dir
    return (Resolve-Path -LiteralPath $combined).ProviderPath
  }
}

function Normalize-PathCanonical {
  param([string]$PathText)
  if ([string]::IsNullOrWhiteSpace($PathText)) { return $PathText }
  $sep = [IO.Path]::DirectorySeparatorChar
  $p = $PathText -replace '[\\/]', [string]$sep
  $full = [IO.Path]::GetFullPath($p)
  if ($full.Length -gt 3) { $full = $full.TrimEnd($sep) }
  return $full
}

function Get-GitTopLevel {
  param([string]$Path)
  $top = (git -C "$Path" rev-parse --show-toplevel 2>$null).Trim()
  if (-not $top) { return $null }
  return (Normalize-PathCanonical $top)
}

function Assert-GitRepository {
  param([string]$Path, [bool]$RequireTopLevel)
  # Confirm we are inside a Git work tree
  $inside = (git -C "$Path" rev-parse --is-inside-work-tree 2>$null).Trim()
  if ($inside -ne 'true') {
    if ($RequireTopLevel) { throw "Path '$Path' is not the root of a Git repository (or not a working tree)." }
    else { throw "Path '$Path' is not inside a Git working tree." }
  }
  # If a root is required, compare normalized paths
  if ($RequireTopLevel) {
    $repoRoot = Get-GitTopLevel -Path $Path
    if (-not $repoRoot) { throw "Could not determine repository toplevel for '$Path'." }
    $normPath = Normalize-PathCanonical $Path
    if (-not [String]::Equals($repoRoot, $normPath, [System.StringComparison]::OrdinalIgnoreCase)) {
      throw "Path mismatch: repo toplevel is '$repoRoot' but script targeted '$normPath'." }
  }
}

function Ensure-GitVersionTool {
  try { $null = & dotnet gitversion /version; return }
  catch {
    Write-Host "GitVersion.Tool not available. Installing locally (tool manifest)..." -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath ".config/dotnet-tools.json")) { dotnet new tool-manifest | Out-Null }
    dotnet tool install GitVersion.Tool --version "*" | Out-Null
  }
}

function Get-GitVersionJson {
  Ensure-GitVersionTool
  $raw = & dotnet gitversion /output json
  return ($raw | ConvertFrom-Json)
}

# Compute a bumped stable SemVer (X.Y.Z) from a SemVer base that might include
# prerelease/build metadata. Exactly one increment must be > 0.
function Compute-BumpedVersion {
  param(
    [string]$SemVerBase,      # e.g., "2.0.44" or "2.0.44-beta.5"
    [int]$IncrementMajor,
    [int]$IncrementMinor,
    [int]$IncrementPatch
  )

  foreach ($n in @($IncrementMajor, $IncrementMinor, $IncrementPatch)) {
    if ($n -lt 0) { throw "Increments must be >= 0." }
  }

  $positive = @($IncrementMajor, $IncrementMinor, $IncrementPatch | Where-Object { $_ -gt 0 })
  if ($positive.Count -gt 1) { throw "Provide only one of -IncrementMajor, -IncrementMinor, or -IncrementPatch (or matching -Bump*)." }
  if ($positive.Count -eq 0) { return $null } # no bump requested

  # Strip prerelease/build
  $numeric = $SemVerBase.Split('-', 2)[0].Split('+', 2)[0]
  if ($numeric -notmatch '^(?<maj>\d+)\.(?<min>\d+)\.(?<pat>\d+)$') {
    throw "Unable to parse SemVer '$SemVerBase' for bumping."
  }

  $maj = [int]$Matches['maj']
  $min = [int]$Matches['min']
  $pat = [int]$Matches['pat']

  if ($IncrementMajor -gt 0) {
    $maj += $IncrementMajor; $min = 0; $pat = 0
  } elseif ($IncrementMinor -gt 0) {
    $min += $IncrementMinor; $pat = 0
  } else {
    $pat += $IncrementPatch
  }

  return "{0}.{1}.{2}" -f $maj, $min, $pat
}

function Test-TagExistsLocal {
  param([string]$TagName)
  $null = git show-ref --verify --quiet "refs/tags/$TagName"
  return ($LASTEXITCODE -eq 0)
}

function Test-TagExistsRemote {
  param([string]$TagName, [string]$Remote = 'origin')
  $out = git ls-remote --tags $Remote "refs/tags/$TagName" 2>$null
  return -not [string]::IsNullOrWhiteSpace($out)
}

# Preserve caller's working dir and initial branch; restore both on exit
$orig = Get-Location
$initialBranch = $null

try {
  $targetDir = Resolve-TargetDirectory -Dir $Directory
  Set-Location -LiteralPath $targetDir

  $requireRoot = -not [string]::IsNullOrWhiteSpace($Directory)
  Assert-GitRepository -Path (Get-Location).Path -RequireTopLevel:$requireRoot

  if (-not $requireRoot) {
    $root = Get-GitTopLevel -Path (Get-Location).Path
    if ($root) { Write-Host "Detected repo root: $root" -ForegroundColor DarkGray }
  }

  # Capture initial branch (after moving into target repo)
  $initialBranch = (git rev-parse --abbrev-ref HEAD).Trim()

  # Switch to requested branch if needed
  if ($initialBranch -ne $Branch) {
    Write-Host "Checking out branch '$Branch' (was '$initialBranch')..." -ForegroundColor Cyan
    git checkout "$Branch" | Out-Null
  }

  if ($Pull) {
    Write-Host "Fetching and pulling latest changes..." -ForegroundColor Cyan
    git fetch --tags origin 2>$null | Out-Null
    git pull --ff-only 2>$null | Out-Null
  }

  $gv = Get-GitVersionJson

  # Resolve effective increments: integers override switches; switches imply +1
  $effMaj = $IncrementMajor
  $effMin = $IncrementMinor
  $effPat = $IncrementPatch
  if ($BumpMajor.IsPresent -and $effMaj -le 0) { $effMaj = 1 }
  if ($BumpMinor.IsPresent -and $effMin -le 0) { $effMin = 1 }
  if ($BumpPatch.IsPresent -and $effPat -le 0) { $effPat = 1 }

  # Compute bumped (stable) version or use FullSemVer as-is
  $bumped = Compute-BumpedVersion -SemVerBase $gv.SemVer `
             -IncrementMajor $effMaj -IncrementMinor $effMin -IncrementPatch $effPat

  # Validate prerelease label (if provided)
  if (-not [string]::IsNullOrWhiteSpace($PreReleaseLabel)) {
    if ($PreReleaseLabel -notmatch '^[0-9A-Za-z\-.]+$') {
      throw "Invalid -PreReleaseLabel '$PreReleaseLabel'. Allowed: letters, digits, '-' and '.'"
    }
  }

  if ($bumped) {
    # If we bumped, optionally apply -PreReleaseLabel
    if (-not [string]::IsNullOrWhiteSpace($PreReleaseLabel)) {
      $versionToTag = "$bumped-$PreReleaseLabel.1"
      $tagMessage   = "Release $versionToTag (bumped from $($gv.FullSemVer))"
    } else {
      $versionToTag = $bumped
      $tagMessage   = "Release $versionToTag (bumped from $($gv.FullSemVer))"
    }
  } else {
    # No bump requested → tag FullSemVer exactly
    $versionToTag = $gv.FullSemVer
    $tagMessage   = "Release $versionToTag"
  }

  # Normalize tag with 'v' prefix
  $tagName = if ($versionToTag -match '^[vV]\d') { $versionToTag } else { "v$versionToTag" }

  if (Test-TagExistsLocal $tagName)  { throw "Tag '$tagName' already exists locally. Aborting." }
  if (Test-TagExistsRemote $tagName) { throw "Tag '$tagName' already exists on 'origin'. Aborting." }

  Write-Host "Tagging '$Branch' at $(git rev-parse --short HEAD) with '$tagName'..." -ForegroundColor Green
  git tag -a "$tagName" -m "$tagMessage"

  Write-Host "Pushing tag '$tagName' to origin..." -ForegroundColor Green
  git push origin "$tagName"

  Write-Host "Done. Created and pushed tag: $tagName" -ForegroundColor Green
}
catch {
  # In case of error, write message in red and re-throw:
  Write-ErrorReport $_.Exception.Message -Throw
}
finally {
  # Restore original branch if we switched and still in a git repo
  try {
    if ($initialBranch) {
      $currentAfter = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
      if ($currentAfter -and $currentAfter -ne $initialBranch) {
        Write-Host "Restoring initial branch '$initialBranch'..." -ForegroundColor DarkGray
        git checkout "$initialBranch" | Out-Null
      }
    }
  } catch { } # best-effort

  # Restore caller's directory
  Set-Location $orig
}
