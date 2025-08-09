<#
.SYNOPSIS
    Attempts to hide the Windows taskbar by patching the StuckRects3 binary registry key.

.DESCRIPTION
    Modifies byte 8 of the "Settings" REG_BINARY in:
      HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3
    to set/clear the taskbar auto-hide bit, then verifies.
    NOTE: Explorer may revert this on some builds; consider HideTaskbar.ps1 (AutoHideTaskbar DWORD) for reliable auto-hide.

.PARAMETER Revert
    Clears the auto-hide bit (disable attempt to hide taskbar).

.PARAMETER AllUsers
    Applies to all users:
      - Pass 1: updates any *loaded* HKEY_USERS\<SID> hives (except current SID).
      - Pass 2: loads offline C:\Users\<name>\NTUSER.DAT into HKU\TempHive_<SID>, updates, then unloads.
    Current user is updated via HKCU at the end.

.PARAMETER RestartExplorer
    Restarts explorer.exe after changes.

#>

param (
    [switch]$Revert,
    [switch]$AllUsers,
    [switch]$RestartExplorer
)

# ---------------- Helpers ----------------

function Test-IsAdministrator {
    $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Explorer {
    Write-Host "Restarting Windows Explorer..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

function Invoke-Reg {
    param(
        [Parameter(Mandatory)][ValidateSet('load','unload')] [string]$Verb,
        [Parameter(Mandatory)][string[]]$Args
    )
    $p = Start-Process -FilePath reg.exe -ArgumentList @($Verb) + $Args -WindowStyle Hidden -Wait -PassThru
    return $p.ExitCode
}

function Set-BinaryRegistryValue {
    param (
        [Parameter(Mandatory)][string]$Hive,       # "HKCU:" or "HKEY_USERS\<sid or tempname>"
        [Parameter(Mandatory)][string]$SubKey,     # e.g. Software\...\StuckRects3
        [Parameter(Mandatory)][string]$ValueName,  # "Settings"
        [Parameter(Mandatory)][bool]  $EnableAutoHide
    )

    $psPath = if ($Hive -match ':$') { "$Hive\$SubKey" } else { "Registry::$Hive\$SubKey" }

    if (-not (Test-Path $psPath)) {
        Write-Warning "Registry path not found: $psPath"
        return $false
    }

    try {
        # Open hive with .NET Reg API
        $root = switch -regex ($Hive) {
            '^HKCU:$'    { [Microsoft.Win32.Registry]::CurrentUser }
            '^HKLM:$'    { [Microsoft.Win32.Registry]::LocalMachine }
            '^HKEY_USERS\\(.+)$' {
                $sid = $Matches[1]
                [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                    [Microsoft.Win32.RegistryHive]::Users,
                    [Microsoft.Win32.RegistryView]::Default
                ).OpenSubKey($sid, $true)
            }
            default { $null }
        }
        if (-not $root) { Write-Warning "Unsupported hive: ${Hive}"; return $false }

        $key = $root.OpenSubKey($SubKey, $true)
        if (-not $key) { Write-Warning "Cannot open subkey $SubKey under ${Hive}"; return $false }

        $bytes = $key.GetValue($ValueName)
        if (-not $bytes -or $bytes.Length -lt 9) {
            Write-Warning "Invalid or missing $psPath\$ValueName"
            $key.Close(); return $false
        }

        # Toggle bit 3 at index 8
        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08
            Write-Host "Enabled auto-hide bit: byte[8] = $($bytes[8])"
        } else {
            $bytes[8] = $bytes[8] -band 0xF7
            Write-Host "Disabled auto-hide bit: byte[8] = $($bytes[8])"
        }

        $key.SetValue($ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
        $key.Close()
        Write-Host "Updated $psPath\$ValueName successfully."

        # Verify
        $actual = (Get-ItemProperty -Path $psPath -Name $ValueName).$ValueName[8]
        if ($actual -eq $bytes[8]) {
            Write-Host "Verification OK: byte[8] = $actual" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "Verification FAILED: byte[8] = $actual (expected $($bytes[8]))"
            return $false
        }
    }
    catch {
        Write-Warning "Error writing to ${Hive}: $_"
        return $false
    }
}

# ---------------- Config ----------------

$subKey         = "Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
$valueName      = "Settings"
$enableAutoHide = -not $Revert

# ---------------- Elevation (with 6s sleep) ----------------

if ($AllUsers -and -not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan
    $scriptPath = $MyInvocation.MyCommand.Path
    $scriptArgs = @()
    if ($Revert)          { $scriptArgs += "-Revert" }
    if ($RestartExplorer) { $scriptArgs += "-RestartExplorer" }
    $scriptArgs += "-AllUsers"

    $cmd = "& `"$scriptPath`" $($scriptArgs -join ' '); Start-Sleep -Seconds 6"
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile","-ExecutionPolicy","Bypass","-Command",$cmd
    )
    exit
}

# ---------------- Apply ----------------

if ($AllUsers) {
    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value

    # Pass 1: Update any *loaded* HKEY_USERS\<SID> hives (skip current SID)
    $loadedSids = ([Microsoft.Win32.RegistryKey]::OpenBaseKey(
                        [Microsoft.Win32.RegistryHive]::Users,
                        [Microsoft.Win32.RegistryView]::Default
                    ).GetSubKeyNames()) |
                  Where-Object { $_ -match '^S-1-5-' -and $_ -ne $currentSid }

    if ($loadedSids.Count -gt 0) {
        Write-Host "Pass 1: Updating loaded hives under HKEY_USERS ..." -ForegroundColor Cyan
        foreach ($sid in $loadedSids) {
            $hive = "HKEY_USERS\$sid"
            $psPath = "Registry::$hive\$subKey"
            if (Test-Path $psPath) {
                $ok = Set-BinaryRegistryValue -Hive $hive -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
                if (-not $ok) { Write-Warning "Failed or skipped for loaded SID ${sid}" }
            } else {
                Write-Warning "StuckRects3 path not found for loaded SID ${sid} - user may never have used Explorer."
            }
        }
    } else {
        Write-Host "No other loaded user hives found under HKEY_USERS." -ForegroundColor Yellow
    }

    # Pass 2: Load *offline* user hives from ProfileList (exclude current SID and any already-loaded)
    $profiles = Get-ChildItem -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
        Where-Object {
            $pi = Get-ItemProperty $_.PSPath
            $pi.ProfileImagePath -and ($pi.ProfileImagePath -like '*\Users\*') -and (Test-Path $pi.ProfileImagePath)
        }

    $offlineProfiles = $profiles | Where-Object { $_.PSChildName -ne $currentSid -and ($loadedSids -notcontains $_.PSChildName) }

    if ($offlineProfiles) {
        Write-Host "Pass 2: Loading offline user hives from ProfileList ..." -ForegroundColor Cyan
    } else {
        Write-Host "No offline user profiles to update." -ForegroundColor Yellow
    }

    foreach ($p in $offlineProfiles) {
        $sid         = $p.PSChildName
        $profilePath = (Get-ItemProperty -Path $p.PSPath).ProfileImagePath
        $ntUserDat   = Join-Path $profilePath 'NTUSER.DAT'
        $tempHive    = "TempHive_$sid"

        if (-not (Test-Path $ntUserDat)) {
            Write-Warning "NTUSER.DAT not found for SID ${sid} at $ntUserDat - skipping"
            continue
        }

        Write-Host "Loading hive for SID ${sid} from $ntUserDat ..."
        $ec = Invoke-Reg -Verb 'load' -Args @("HKU\$tempHive", $ntUserDat)
        if ($ec -ne 0) {
            Write-Warning "Could not load hive for SID ${sid} (ExitCode=$ec). Is the user logged in or file locked?"
            continue
        }

        try {
            $ok = Set-BinaryRegistryValue -Hive "HKEY_USERS\$tempHive" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
            if (-not $ok) {
                Write-Warning "Update failed under HKEY_USERS\$tempHive for SID ${sid}"
            }
        } finally {
            Write-Host "Unloading hive for SID ${sid} ..."
            $ec2 = Invoke-Reg -Verb 'unload' -Args @("HKU\$tempHive")
            if ($ec2 -ne 0) {
                Write-Warning "Could not unload hive for SID ${sid} (ExitCode=$ec2). You may need to log off that user."
            }
        }
    }

    # Finally, update the current user via HKCU
    Write-Host "Updating current user (HKCU)..." -ForegroundColor Cyan
    Set-BinaryRegistryValue -Hive "HKCU:" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
}
else {
    # Single-user
    Set-BinaryRegistryValue -Hive "HKCU:" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
}

# ---------------- Finish ----------------

if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log off and log back in for changes to take effect." -ForegroundColor Cyan
}
