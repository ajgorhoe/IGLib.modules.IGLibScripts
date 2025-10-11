
# Copyright © Igor Grešovnik.
# Part of IGLib: https://github.com/ajgorhoe/IGLib.modules.IGLibScripts
# License:
# https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/LICENSE.md

<#
.SYNOPSIS
  Synchronize tags across multiple repositories by tagging each repo's branch
  (default: main, with fallback to master) with a common version.

.DESCRIPTION
  Two-pass process:
  1) Pass 1 (inspect): For each repo, check out the target branch (default 'main';
     fall back to 'master' if 'main' doesn't exist), optionally pull, and compute
     the version via GitVersion. Collect each repo’s version.
  2) Choose the MAX version among repos by (Major, Minor, Patch). Optionally apply
     a single bump/increment (Major/Minor/Patch). If -PreReleaseLabel is provided
     AND a bump occurred, set final tag to X.Y.Z-<label>.1. Prefix with 'v'.
  3) Pass 2 (apply): Tag & push the final tag on the chosen branch for each repo.
     Skip repos that are already at that tag.

  Each per-repo pass:
    - Validates repo root
    - Restores original branch and working directory
    - Returns a result object; never throws to the caller

.PARAMETER RepoDirs
  Array of repository directory paths (absolute or relative to the script directory).
  Each must be the ROOT of the Git repository.

.PARAMETER Branch
  Target branch (default 'main'). In Pass 1, if a repo lacks 'main', we fall back
  to 'master'. The effective branch used is stored and reused in Pass 2.

.PARAMETER Pull
  If set, Pass 1 fetches tags and pulls latest changes (ff-only) before versioning.

.PARAMETER BumpMajor
  If set (and -IncrementMajor is 0), bump MAJOR by 1 (resets Minor/Patch to 0).

.PARAMETER BumpMinor
  If set (and -IncrementMinor is 0), bump MINOR by 1 (resets Patch to 0).

.PARAMETER BumpPatch
  If set (and -IncrementPatch is 0), bump PATCH by 1.

.PARAMETER IncrementMajor
  Integer (default 0). If > 0, bump MAJOR by that amount (resets Minor/Patch to 0).
  Overrides -BumpMajor.

.PARAMETER IncrementMinor
  Integer (default 0). If > 0, bump MINOR by that amount (resets Patch to 0).
  Overrides -BumpMinor.

.PARAMETER IncrementPatch
  Integer (default 0). If > 0, bump PATCH by that amount.
  Overrides -BumpPatch.

.PARAMETER PreReleaseLabel
  Optional prerelease label to apply AFTER a bump/increment. If supplied AND a bump
  occurred, final tag becomes X.Y.Z-<label>.1. Allowed chars: [0-9A-Za-z-.].
  Ignored if no bump occurs.

.PARAMETER DryRun
  If set, performs all operations except actually creating or pushing tags.

.EXAMPLE
  .\SyncTagVersions.ps1 -RepoDirs ..\RepoA, ..\RepoB
  # Inspects versions on 'main' (fallback to 'master'), picks maximum, tags both.

.EXAMPLE
  .\SyncTagVersions.ps1 -RepoDirs C:\src\RepoA, C:\src\RepoB -Pull -BumpPatch
  # Pulls first, picks maximum, bumps PATCH by 1, tags both.

.EXAMPLE
  .\SyncTagVersions.ps1 -RepoDirs .\RepoA, .\RepoB -IncrementMinor 2 -PreReleaseLabel rc
  # Picks maximum, bumps MINOR by +2, applies '-rc.1', tags both.
#>

[CmdletBinding()]
param(
  [Parameter(Mandatory)]
  [string[]] $RepoDirs,

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

# We don't want Write-Error to stop the script, but we want to see errors;
# use default ('Continue'):
$ErrorActionPreference = 'Continue' # Never stop; handle errors manually

# ---------- Utility helpers ----------

# Writes a red message; if -Throw switch is on, also throws exception 
# with this message.
function Write-ErrorReport {
    param([string]$Message, [switch]$Throw)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    if ($Throw) {
        throw $Message
    }
}

# Invoke a native command and return structured result (PS 5.1 safe)
function Invoke-Native {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [string[]]$ArgumentList
  )
  $output = & $FilePath @ArgumentList 2>&1
  [PSCustomObject]@{
    Output = $output
    ExitCode = $LASTEXITCODE
  }
}

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

function Is-GitRoot {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) { return $false }
  $inside = (git -C "$Path" rev-parse --is-inside-work-tree 2>$null).Trim()
  if ($inside -ne 'true') { return $false }
  $top = (git -C "$Path" rev-parse --show-toplevel 2>$null).Trim()
  if (-not $top) { return $false }
  $normTop  = Resolve-CanonicalPath $top
  $normPath = Resolve-CanonicalPath $Path
  return [String]::Equals($normTop, $normPath, [StringComparison]::OrdinalIgnoreCase)
}

function Ensure-GitVersionTool {
  try { $null = & dotnet gitversion /version; return $true } catch {
    Write-Host "  GitVersion.Tool not available. Installing local tool..." -ForegroundColor Yellow
    if (-not (Test-Path -LiteralPath ".config/dotnet-tools.json")) { dotnet new tool-manifest | Out-Null }
    dotnet tool install GitVersion.Tool --version "*" | Out-Null
    try { $null = & dotnet gitversion /version; return $true } catch { return $false }
  }
}

function Get-GitVersionJson {
  try {
    $raw = & dotnet gitversion /output json
    return ($raw | ConvertFrom-Json)
  } catch { return $null }
}

function Parse-SemVerBase {
  param([string]$SemVerLike)
  if ([string]::IsNullOrWhiteSpace($SemVerLike)) { return $null }
  $numeric = $SemVerLike.Split('-', 2)[0].Split('+', 2)[0]
  if ($numeric -notmatch '^(?<maj>\d+)\.(?<min>\d+)\.(?<pat>\d+)$') { return $null }
  return ,([int[]]@([int]$Matches['maj'], [int]$Matches['min'], [int]$Matches['pat']))
}

function Compute-BumpedVersion {
  <# Return stable X.Y.Z after applying exactly one increment (>0). #>
  param(
    [string]$SemVerBase,
    [int]$IncrementMajor,
    [int]$IncrementMinor,
    [int]$IncrementPatch
  )
  foreach ($n in @($IncrementMajor, $IncrementMinor, $IncrementPatch)) {
    if ($n -lt 0) { throw "Increments must be >= 0." }
  }
  $count = 0
  if ($IncrementMajor -gt 0) { $count++ }
  if ($IncrementMinor -gt 0) { $count++ }
  if ($IncrementPatch -gt 0) { $count++ }
  if ($count -gt 1) { throw "Specify only one increment among Major/Minor/Patch." }
  if ($count -eq 0) { return $null }

  $parts = Parse-SemVerBase $SemVerBase
  if ($null -eq $parts) { throw "Unable to parse SemVer '$SemVerBase' for bumping." }
  $maj = $parts[0]; $min = $parts[1]; $pat = $parts[2]

  if     ($IncrementMajor -gt 0) { $maj += $IncrementMajor; $min = 0; $pat = 0 }
  elseif ($IncrementMinor -gt 0) { $min += $IncrementMinor; $pat = 0 }
  else                           { $pat += $IncrementPatch }

  return ("{0}.{1}.{2}" -f $maj, $min, $pat)
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

# ---------- Per-repo operations (pass 1 & 2) ----------

function Invoke-RepoFirstPass {
  <#
    Validate root, select target branch (fallback to master if main missing),
    optional pull, compute GitVersion's FullSemVer.
    Never throw; return result object.
  #>
  param(
    [string]$OrigPath,
    [string]$AbsPath,
    [string]$Branch,
    [switch]$Pull
  )

  Write-Host "  Checking repository at '$OrigPath' ..." -ForegroundColor DarkCyan

  $result = [PSCustomObject]@{
    OrigPath   = $OrigPath
    AbsPath    = $AbsPath
    RepoName   = (Split-Path -Leaf $AbsPath)
    Branch     = $Branch
    UsedBranch = $null
    Version    = $null
    Error      = $null
    Success    = $false
  }

  $origLoc = Get-Location
  $initialBranch = $null
  Write-Host "    Setting and validating dir: '$AbsPath' ..." -ForegroundColor DarkCyan
  try {
    Set-Location -LiteralPath $AbsPath

    if (-not (Is-GitRoot $AbsPath)) {
      $result.Error = "Not a valid Git repository root."
      Write-ErrorReport "    ERROR: $result.Error "
      return $result
    }

    # What branch are we on now?
    $initialBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()

    # Decide which branch to use:
    # - If requested Branch exists locally, use it.
    # - Else if Branch == main and master exists, fall back to master.
    # - Else error.
    $target = $Branch
    Write-Host "    Checking out '$target' ..." -ForegroundColor DarkCyan

    $null = git show-ref --verify --quiet ("refs/heads/" + $target)
    $existsRequested = ($LASTEXITCODE -eq 0)

    if (-not $existsRequested -and $Branch -eq 'main') {
      $null = git show-ref --verify --quiet "refs/heads/master"
      if ($LASTEXITCODE -eq 0) {
		Write-Host "    Checking out 'master' branch ..." -ForegroundColor DarkCyan
        $target = 'master'
        Write-Host "    Falling back from 'main' to 'master' for this repo." -ForegroundColor DarkYellow
      }
    }

    # Re-check existence for the decided target
    $null = git show-ref --verify --quiet ("refs/heads/" + $target)
    $existsTarget = ($LASTEXITCODE -eq 0)
    if (-not $existsTarget) {
      $result.Error = "Target branch '$target' does not exist locally."
      Write-ErrorReport "    ERROR: $result.Error "
      return $result
    }

    # Switch only if needed
    if ($initialBranch -ne $target) {
      Write-Host "    Checking out '$target' ..." -ForegroundColor DarkCyan
      $null = git checkout "$target" 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0) {
        $result.Error = "Failed to checkout branch '$target'."
        return $result
      }
    } else {
      Write-Host "    Already on '$target'." -ForegroundColor DarkGray
    }

    $result.UsedBranch = $target

    if ($Pull) {
      Write-Host ("    Pulling latest on '{0}' ..." -f $target) -ForegroundColor DarkCyan
      $null = git fetch --tags origin 2>$null | Out-Null
      $null = git pull --ff-only 2>$null | Out-Null
      # No need to hard-fail on pull non-zero; GitVersion can still compute
    }

	Write-Host "    Ensuring that GitVersion is available ..." -ForegroundColor DarkCyan
    if (-not (Ensure-GitVersionTool)) {
      $result.Error = "GitVersion.Tool installation failed."
      Write-ErrorReport "    ERROR: $result.Error "
      return $result
    }

    Write-Host "    Retrieving the current version ..." -ForegroundColor DarkCyan
    $gv = Get-GitVersionJson
    if ($null -eq $gv -or [string]::IsNullOrWhiteSpace($gv.FullSemVer)) {
      $result.Error = "GitVersion did not return a valid version."
      Write-ErrorReport "    ERROR: $result.Error "
      return $result
    }

    $result.Version = $gv.FullSemVer
    $result.Success = $true
    Write-Host "    Returning current version: $result.Version " -ForegroundColor DarkCyan
    return $result
  }
  catch {
    $result.Error = $_.Exception.Message
    Write-ErrorReport "    ERROR caught: $result.Error "
    return $result
  }
  finally {
    # Restore original branch and directory
    try {
      if ($initialBranch) {
        $curr = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($curr -and ($curr -ne $initialBranch)) {
          $null = git checkout "$initialBranch" 2>$null | Out-Null
        }
      }
    } catch {
      $result.Error = $_.Exception.Message
      Write-ErrorReport "    ERROR when restoring the branch: $result.Error "
    }
    Set-Location $origLoc
  }
}

function Invoke-RepoSecondPass {
  <#
    Validate root, checkout UsedBranch, apply tag if needed, push, recalc version.
    Never throw; return result object.
  #>
  param(
    [string]$OrigPath,
    [string]$AbsPath,
    [string]$UsedBranch,
    [string]$TagToApply
  )

  $result = [PSCustomObject]@{
    OrigPath   = $OrigPath
    AbsPath    = $AbsPath
    RepoName   = (Split-Path -Leaf $AbsPath)
    Branch     = $UsedBranch
    AppliedTag = $TagToApply
    Recalc     = $null
    Skipped    = $false
    Error      = $null
    Success    = $false
  }

  $origLoc = Get-Location
  $initialBranch = $null
  Write-Host "    Setting and validating dir: '$AbsPath' ..." -ForegroundColor DarkCyan
  try {
    Set-Location -LiteralPath $AbsPath

    if (-not (Is-GitRoot $AbsPath)) {
      $result.Error = "Not a valid Git repository root."
      return $result
    }

    $initialBranch = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()

    # Ensure target branch exists locally before switching
    $null = git show-ref --verify --quiet ("refs/heads/" + $UsedBranch)
    if ($LASTEXITCODE -ne 0) {
      $result.Error = "Branch '$UsedBranch' does not exist locally."
      Write-ErrorReport "    ERROR: $result.Error "
      return $result
    }

    if ($initialBranch -ne $UsedBranch) {
      $null = git checkout "$UsedBranch" 2>$null | Out-Null
      if ($LASTEXITCODE -ne 0) {
        $result.Error = "Cannot check out branch '$UsedBranch'."
        Write-ErrorReport "    ERROR: $result.Error "
        return $result
      }
    }

    $tag = $TagToApply
    if (Test-TagExistsLocal $tag -or Test-TagExistsRemote $tag) {
      $result.Skipped = $true
      Write-Host ("    [{0}] tag '{1}' already exists (local or remote) - skipping." -f $result.RepoName, $tag) -ForegroundColor DarkYellow
    } else {
        Write-Host ("    [{0}] tagging '{1}' with '{2}' ..." -f $result.RepoName, $UsedBranch, $tag) -ForegroundColor Green
        # Execute: git tag -a "$tag" -m "Sync release $tag"
        $r = Invoke-Native git @('tag', '-a', "$tag", '-m', "Sync version $tag")
        if ($r.ExitCode -ne 0) {
          $result.Error = "Failed to create tag '$tag'."
          Write-ErrorReport "    ERROR creating tag: $result.Error "
          return $result
        } else {
          Write-Host "      ... tagging performed successfully." -ForegroundColor DarkCyan
        }
        Write-Host ("    [{0}] pushing tag '{1}' to origin ..." -f $result.RepoName, $tag) -ForegroundColor Green
        # Execute: git push origin "$tag"
        $r = Invoke-Native git @('push', 'origin')
        if ($r.ExitCode -ne 0) {
          $result.Error = "Failed to push tag '$tag' to origin."
          Write-ErrorReport "    ERROR pushing tag: $result.Error "
          return $result
        } else {
          Write-Host "      ... tag pushed successfully." -ForegroundColor DarkCyan
        }
    }

    Write-Host "    Ensure that GitVersion is available..." -ForegroundColor DarkCyan
    if (-not (Ensure-GitVersionTool)) {
      $result.Error = "GitVersion.Tool installation failed for recalculation."
      Write-ErrorReport "    ERROR: $result.Error "
      return $result
    }

    Write-Host "    Re-calculating version information..." -ForegroundColor DarkCyan
    $gv2 = Get-GitVersionJson
    if ($null -eq $gv2 -or [string]::IsNullOrWhiteSpace($gv2.FullSemVer)) {
      $result.Error = "GitVersion did not return a valid version after tagging."
      Write-ErrorReport "    ERROR: $result.Error "
      return $result
    }

    $result.Recalc  = $gv2.FullSemVer
    $result.Success = $true
    return $result
  }
  catch {
    $result.Error = $_.Exception.Message
    Write-ErrorReport "    ERROR caught in Invoke-RepoSecondPass: $result.Error "
    return $result
  }
  finally {
    try {
      if ($initialBranch) {
        $curr = (git rev-parse --abbrev-ref HEAD 2>$null).Trim()
        if ($curr -and ($curr -ne $initialBranch)) {
          $null = git checkout "$initialBranch" 2>$null | Out-Null
        }
      }
    } catch { 
      $result.Error = $_.Exception.Message
      Write-ErrorReport "    ERROR caught when restoring the branch: $result.Error "
    }
    Set-Location $origLoc
  }
}

# ---------- Param echo / preprocessing ----------

# Effective increments: integers override switches; switches imply +1
$effMaj = $IncrementMajor
$effMin = $IncrementMinor
$effPat = $IncrementPatch
if ($BumpMajor.IsPresent -and $effMaj -le 0) { $effMaj = 1 }
if ($BumpMinor.IsPresent -and $effMin -le 0) { $effMin = 1 }
if ($BumpPatch.IsPresent -and $effPat -le 0) { $effPat = 1 }

if (-not [string]::IsNullOrWhiteSpace($PreReleaseLabel)) {
  if ($PreReleaseLabel -notmatch '^[0-9A-Za-z\-.]+$') {
    throw "Invalid -PreReleaseLabel '$PreReleaseLabel'. Allowed: letters, digits, '-' and '.'"
  }
}

Write-Host `n`n"=== SyncTagVersions parameters ===" -ForegroundColor Cyan
Write-Host ("Repos: {0}" -f ($RepoDirs -join ", "))
Write-Host ("Branch: {0}  (fallback to 'master' per-repo if 'main' missing)" -f $Branch)
Write-Host ("Pull: {0}" -f ($Pull.IsPresent))
Write-Host ("Increments -> Major:{0} Minor:{1} Patch:{2}" -f $effMaj, $effMin, $effPat)
$preText = "<none>"
if (-not [string]::IsNullOrWhiteSpace($PreReleaseLabel)) { $preText = $PreReleaseLabel }
Write-Host ("PreReleaseLabel: {0}" -f $preText)
Write-Host "==================================" -ForegroundColor Cyan

# Build rows
$rows = @()
foreach ($rp in $RepoDirs) {
  $abs = Resolve-CanonicalPath $rp
  $rows += [PSCustomObject]@{
    OrigPath   = $rp
    AbsPath    = $abs
    RepoName   = (Split-Path -Leaf $abs)
    Branch     = $Branch
    UsedBranch = $null
    Version1   = $null
    FinalTag   = $null
    Version2   = $null
    Error1     = $null
    Error2     = $null
    Skipped2   = $false
  }
}

# ---------- Pass 1 ----------

Write-Host "`n--- Pass 1: compute per-repo versions ---" -ForegroundColor Cyan
for ($i=0; $i -lt $rows.Count; $i++) {
  $row = $rows[$i]
  Write-Host ("[{0}/{1}] {2}" -f ($i+1), $rows.Count, $row.OrigPath) -ForegroundColor DarkCyan

  $r = Invoke-RepoFirstPass -OrigPath $row.OrigPath -AbsPath $row.AbsPath -Branch $row.Branch -Pull:$Pull
  if ($null -eq $r) {
    $row.Error1 = "Unknown error (null result)"
    continue
  }
  $row.UsedBranch = $r.UsedBranch
  if ($r.Success) { $row.Version1 = $r.Version } else { $row.Error1 = $r.Error }
}

Write-Host "`n=== Survey after Pass 1 (current versions) ===" -ForegroundColor Cyan
foreach ($row in $rows) {
  $verText = "''"
  if (-not [string]::IsNullOrWhiteSpace($row.Version1)) { $verText = "'" + $row.Version1 + "'" }
  $used = $row.Branch
  if (-not [string]::IsNullOrWhiteSpace($row.UsedBranch)) { $used = $row.UsedBranch }
  Write-Host ("{0,-25}  Orig='{1}'  Branch={2}  Version={3}" -f $row.RepoName, $row.OrigPath, $used, $verText)
}
Write-Host "==============================================" -ForegroundColor Cyan

# ---------- Pick maximum (by Major/Minor/Patch) ----------

$versionsForMax = @()
foreach ($row in $rows) {
  if (-not [string]::IsNullOrWhiteSpace($row.Version1)) {
    $tuple = Parse-SemVerBase $row.Version1
    if ($null -ne $tuple) {
      $versionsForMax += [PSCustomObject]@{
        Row   = $row
        Base  = $row.Version1
        Tuple = $tuple
      }
    }
  }
}

if (-not $versionsForMax -or $versionsForMax.Count -eq 0) {
  Write-Host "`nNo valid versions found in Pass 1; nothing to tag." -ForegroundColor Yellow
  return
}

# Sort and pick first
$maxItem = $versionsForMax | Sort-Object `
  @{Expression={ $_.Tuple[0] };Descending=$true}, `
  @{Expression={ $_.Tuple[1] };Descending=$true}, `
  @{Expression={ $_.Tuple[2] };Descending=$true} `
  | Select-Object -First 1

$selectedBase = $maxItem.Base
Write-Host ("`nSelected base version (max Major/Minor/Patch): {0}" -f $selectedBase) -ForegroundColor Green

# Apply increments
$finalBase = $selectedBase
$didBump = $false
try {
  $maybe = Compute-BumpedVersion -SemVerBase $selectedBase -IncrementMajor $effMaj -IncrementMinor $effMin -IncrementPatch $effPat
  if (-not [string]::IsNullOrWhiteSpace($maybe)) {
    $finalBase = $maybe
    $didBump = $true
  }
} catch {
  Write-Host ("Error applying increments: {0}" -f $_.Exception.Message) -ForegroundColor Yellow
}

# Apply prerelease label if a bump occurred and label was provided
$finalVersion = $finalBase
if ($didBump -and -not [string]::IsNullOrWhiteSpace($PreReleaseLabel)) {
  $finalVersion = $finalBase + "-" + $PreReleaseLabel + ".1"
}

# Normalize final tag with 'v' prefix
$finalTag = $finalVersion
if ($finalTag -notmatch '^[vV]\d') { $finalTag = "v" + $finalTag }

Write-Host ("Final synchronized tag to apply: {0}" -f $finalTag) -ForegroundColor Green

# ---------- Pass 2 ----------

if ($DryRun.IsPresent) {
  Write-Host "`nDRY RUN mode; no tags are created or pushed.`n" -ForegroundColor Yellow
} else {

  Write-Host "`n--- Pass 2: apply tag to all repos ---" -ForegroundColor Cyan
  for ($i=0; $i -lt $rows.Count; $i++) {
    $row = $rows[$i]
    Write-Host ("[{0}/{1}] {2}" -f ($i+1), $rows.Count, $row.OrigPath) -ForegroundColor DarkCyan

    # Determine what tag pass 1 implied for this repo (normalize with 'v')
    $rowFirstTag = $null
    if (-not [string]::IsNullOrWhiteSpace($row.Version1)) {
      $rowFirstTag = $row.Version1
      if ($rowFirstTag -notmatch '^[vV]\d') { $rowFirstTag = "v" + $rowFirstTag }
    }

    $already = $false
    if (-not [string]::IsNullOrWhiteSpace($rowFirstTag)) {
      if ([String]::Equals($rowFirstTag, $finalTag, [StringComparison]::OrdinalIgnoreCase)) {
        $already = $true
      }
    }

    if ($already) {
      # Remark: even if the version matches, the tag might not exist (locally or remotely).
      # So we report the match but do NOT skip; we still attempt to apply the tag.
      Write-Host ("  [{0}] version already matches '{1}', still attempting to apply the tag." -f $row.RepoName, $finalTag) -ForegroundColor DarkYellow
      # $row.FinalTag = $finalTag
      # $row.Skipped2 = $true
      # continue
    }

    $used = $row.Branch
    if (-not [string]::IsNullOrWhiteSpace($row.UsedBranch)) { $used = $row.UsedBranch }

    try {
      $r2 = Invoke-RepoSecondPass -OrigPath $row.OrigPath -AbsPath $row.AbsPath -UsedBranch $used -TagToApply $finalTag
      if ($null -eq $r2) {
        $row.Error2 = "Unknown error (null result)"
        continue
      }
    }
    catch {
      Write-ErrorReport "ERROR caught in Invoke-RepoSecondPass: $($_.Exception.Message)"
      continue
    }

    $row.FinalTag = $finalTag
    $row.Skipped2 = $r2.Skipped
    if ($r2.Success) { $row.Version2 = $r2.Recalc } else { $row.Error2 = $r2.Error }
  }

  Write-Host "`n=== Survey after Pass 2 (tag results) ===" -ForegroundColor Cyan
  foreach ($row in $rows) {
    $v1 = "''"; if (-not [string]::IsNullOrWhiteSpace($row.Version1)) { $v1 = "'" + $row.Version1 + "'" }
    $tagOut = "''"; if (-not [string]::IsNullOrWhiteSpace($row.FinalTag)) { $tagOut = "'" + $row.FinalTag + "'" }
    $v2 = "''"; if (-not [string]::IsNullOrWhiteSpace($row.Version2)) { $v2 = "'" + $row.Version2 + "'" }
    $used = $row.Branch; if (-not [string]::IsNullOrWhiteSpace($row.UsedBranch)) { $used = $row.UsedBranch }
    $flag = ""
    if ($row.Skipped2) { $flag = " (skipped)" }
    elseif (-not [string]::IsNullOrWhiteSpace($row.Error2)) { $flag = " (error)" }
    Write-Host ("{0,-25}  Orig='{1}'  Branch={2}  V1={3}  Tag={4}  V2={5}{6}" -f $row.RepoName, $row.OrigPath, $used, $v1, $tagOut, $v2, $flag)
    if (-not [string]::IsNullOrWhiteSpace($row.Error1)) { Write-Host ("  Pass1 error: {0}" -f $row.Error1) -ForegroundColor DarkRed }
    if (-not [string]::IsNullOrWhiteSpace($row.Error2)) { Write-Host ("  Pass2 error: {0}" -f $row.Error2) -ForegroundColor DarkRed }
  }

} # if not DryRun
Write-Host "===================== SyncTagVersions completed.`n" -ForegroundColor Cyan
