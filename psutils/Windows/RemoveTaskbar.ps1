<#
.SYNOPSIS
  Toggle the taskbar auto-hide bit in StuckRects3\Settings (byte[8], bit 0x08).

.DESCRIPTION
  For the current user (HKCU), sets or clears bit 3 (0x08) in:
    HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3 (REG_BINARY "Settings")

  - Without switches: enables auto-hide (sets bit 0x08)
  - With -Revert:     disables auto-hide (clears bit 0x08)
  - With -RestartExplorer: restarts Explorer for the current session
  - With -AllUsers: replicates the setting to other user profiles where possible
      • Updates HKCU for the current user
      • For other users:
          - If HKEY_USERS\<SID> hive is loaded → write directly
          - If hive is not loaded but profile is offline → attempt to load NTUSER.DAT temporarily
          - Skip service/system SIDs (S-1-5-18/19/20, S-1-5-80-*)
      • Produces a concise report summary at the end of the -AllUsers branch

.NOTES
  • Some users may need to log off/on for the change to take effect.
  • StuckRects3 may not exist for some profiles until the user logs in at least once.
#>

[CmdletBinding()]
param(
    [switch]$Revert,
    [switch]$AllUsers,
    [switch]$RestartExplorer
)

# ---------------- Utilities ----------------

function Test-IsAdmin {
    try {
        $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr  = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

function Restart-Explorer {
    Write-Host "Restarting Windows Explorer..."
    try {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    } catch {
        Write-Warning "Failed to restart Explorer: $($_.Exception.Message)"
    }
}

# --- Summary helpers for -AllUsers -----------------------------------------
function New-AllUsersReport {
    [ordered]@{
        Considered        = 0
        UpdatedHKCU       = $false
        UpdatedOtherCount = 0
        UpdatedOtherSIDs  = @()
        SkippedService    = @()
        SkippedHiveInUse  = @()
        SkippedNoHive     = @()
        FailedWrites      = @()
    }
}

function Write-AllUsersSummary {
    param([hashtable]$Report)
    Write-Host ""
    Write-Host "=== All-Users summary ===" -ForegroundColor Cyan
    Write-Host ("Profiles considered        : {0}" -f $Report.Considered)
    Write-Host ("Updated current user (HKCU): {0}" -f ($(if ($Report.UpdatedHKCU) { 'Yes' } else { 'No' })))
    Write-Host ("Updated other users        : {0}" -f $Report.UpdatedOtherCount)
    if ($Report.UpdatedOtherSIDs.Count) {
        Write-Host ("  SIDs: {0}" -f ($Report.UpdatedOtherSIDs -join ', '))
    }
    if ($Report.SkippedService.Count) {
        Write-Host ("Skipped service/system SIDs: {0}" -f ($Report.SkippedService -join ', '))
    }
    if ($Report.SkippedHiveInUse.Count) {
        Write-Host ("Hives locked (skipped)     : {0}" -f ($Report.SkippedHiveInUse -join ', '))
    }
    if ($Report.SkippedNoHive.Count) {
        Write-Host ("Hives unavailable (skipped): {0}" -f ($Report.SkippedNoHive -join ', '))
    }
    if ($Report.FailedWrites.Count) {
        Write-Host ("Failed writes              : {0}" -f ($Report.FailedWrites -join ', '))
    }
}

# ------------- Core registry update -------------

function Set-StuckRects3AutoHide {
    param(
        [Parameter(Mandatory)][string]$HiveRoot,   # e.g., HKCU: or Registry::HKEY_USERS\S-1-5-21-...\TempHive_foo
        [switch]$EnableAutoHide
    )
    $srKey = Join-Path $HiveRoot 'Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3'
    try {
        if (-not (Test-Path -LiteralPath $srKey)) {
            Write-Warning "Registry path not found:`n${srKey}"
            return $false
        }
        $prop = Get-ItemProperty -LiteralPath $srKey -Name 'Settings' -ErrorAction Stop
        [byte[]]$bytes = $prop.Settings

        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08
            Write-Host ("Enabled auto-hide bit: byte[8] = {0}" -f $bytes[8])
        } else {
            $bytes[8] = $bytes[8] -band 0xF7
            Write-Host ("Disabled auto-hide bit: byte[8] = {0}" -f $bytes[8])
        }

        Set-ItemProperty -LiteralPath $srKey -Name 'Settings' -Value $bytes -ErrorAction Stop

        # Verify
        $verify = (Get-ItemProperty -LiteralPath $srKey -Name 'Settings' -ErrorAction Stop).Settings
        if ($verify[8] -eq $bytes[8]) {
            Write-Host ("Updated {0} successfully." -f (Join-Path $srKey 'Settings'))
            return $true
        } else {
            Write-Warning ("Verification mismatch at {0} (expected {1}, got {2})" -f (Join-Path $srKey 'Settings'), $bytes[8], $verify[8])
            return $false
        }
    } catch {
        Write-Warning "Failed to update ${srKey}: $($_.Exception.Message)"
        return $false
    }
}

# ------------- Elevation for -AllUsers -------------

if ($AllUsers -and -not (Test-IsAdmin)) {
    Write-Host "Elevation required. Relaunching as administrator..."
    # Build a single command string to avoid ArgumentList array binding issues
    $script = '"' + $PSCommandPath + '"'
    $args   = @()
    if ($Revert)           { $args += '-Revert' }
    if ($AllUsers)         { $args += '-AllUsers' }
    if ($RestartExplorer)  { $args += '-RestartExplorer' }
    $joined = $args -join ' '
    $full   = "& $script $joined; Start-Sleep -Seconds 6"
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $full"
    exit
}

# ----------------- Main -----------------

$enable = -not $Revert

if (-not $AllUsers) {
    # Current user only (HKCU)
    $ok = Set-StuckRects3AutoHide -HiveRoot 'HKCU:' -EnableAutoHide:$enable
    if ($RestartExplorer) { Restart-Explorer }
    if (-not $ok) {
        Write-Host "You may need to restart Explorer or log off and log back in for changes to take effect."
    }
    return
}

# -AllUsers branch
$Report = New-AllUsersReport

# 1) Current user via HKCU
$okHKCU = Set-StuckRects3AutoHide -HiveRoot 'HKCU:' -EnableAutoHide:$enable
if ($okHKCU) { $Report.UpdatedHKCU = $true }

# 2) Other profiles
# Enumerate from ProfileList to get SIDs and profile paths
$plRoot = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
$profiles = @()
try {
    $profiles = Get-ChildItem -LiteralPath $plRoot -ErrorAction Stop | Where-Object { $_.PSChildName -match '^S-1-5-21-' } | ForEach-Object {
        $sid  = $_.PSChildName
        $path = (Get-ItemProperty -LiteralPath $_.PsPath -Name 'ProfileImagePath' -ErrorAction SilentlyContinue).ProfileImagePath
        [PSCustomObject]@{ Sid = $sid; ProfilePath = $path }
    }
} catch {
    Write-Warning "Failed to enumerate ProfileList: $($_.Exception.Message)"
    $profiles = @()
}

# Add any loaded hives under HKEY_USERS (that look like user SIDs)
try {
    $loaded = Get-ChildItem Registry::HKEY_USERS -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^S-1-5-21-' } |
        ForEach-Object { $_.PSChildName }
    foreach ($sid in $loaded) {
        if (-not ($profiles.Sid -contains $sid)) {
            $profiles += [PSCustomObject]@{ Sid = $sid; ProfilePath = $null }
        }
    }
} catch { }

# Current user SID
$currentSid = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value

foreach ($p in $profiles) {
    $sid = $p.Sid

    # Skip current user (already handled)
    if ($sid -eq $currentSid) { continue }

    # Skip service/system SIDs if somehow present
    if ($sid -in @('S-1-5-18','S-1-5-19','S-1-5-20') -or $sid -like 'S-1-5-80-*') {
        $Report.SkippedService += $sid
        continue
    }

    $Report.Considered++

    $hkuPath = "Registry::HKEY_USERS\${sid}\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    if (Test-Path -LiteralPath $hkuPath) {
        # Hive loaded; write directly
        $root = "Registry::HKEY_USERS\${sid}"
        if (Set-StuckRects3AutoHide -HiveRoot $root -EnableAutoHide:$enable) {
            $Report.UpdatedOtherCount++
            $Report.UpdatedOtherSIDs += $sid
        } else {
            $Report.FailedWrites += $sid
        }
        continue
    }

    # Try to load offline hive if we have a profile path
    if ($p.ProfilePath -and (Test-Path -LiteralPath (Join-Path $p.ProfilePath 'NTUSER.DAT'))) {
        $tempName = "TempHive_${sid}"
        $ntuser   = Join-Path $p.ProfilePath 'NTUSER.DAT'
        Write-Host "Loading hive for SID ${sid}..."
        $load = & reg.exe load "HKU\${tempName}" "$ntuser" 2>&1
        if ($LASTEXITCODE -ne 0) {
            if ($load -match 'in use|being used by another process') {
                $Report.SkippedHiveInUse += $sid
            } else {
                $Report.SkippedNoHive += $sid
            }
            continue
        }

        try {
            $root = "Registry::HKEY_USERS\${tempName}"
            if (Set-StuckRects3AutoHide -HiveRoot $root -EnableAutoHide:$enable) {
                $Report.UpdatedOtherCount++
                $Report.UpdatedOtherSIDs += $sid
            } else {
                $Report.FailedWrites += $sid
            }
        } finally {
            Write-Host "Unloading hive for SID ${sid}..."
            & reg.exe unload "HKU\${tempName}" | Out-Null
        }
    } else {
        $Report.SkippedNoHive += $sid
    }
}

Write-AllUsersSummary -Report $Report

if ($RestartExplorer) { Restart-Explorer }

Write-Host "You may need to restart Explorer or log off and log back in for changes to take effect."
