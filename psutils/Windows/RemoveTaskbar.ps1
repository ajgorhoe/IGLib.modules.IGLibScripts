<#
.SYNOPSIS
    Attempts to hide the Windows taskbar by patching the StuckRects3 binary registry key.

.DESCRIPTION
    Modifies byte 8 of the "Settings" value in:
      HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3
    to set or clear the taskbar auto-hide flag, then verifies.
    Supports:
      -Revert         : clears the auto-hide bit
      -AllUsers       : loads each user's hive (requires elevation)
      -RestartExplorer: restarts explorer.exe immediately
#>

param (
    [switch]$Revert,
    [switch]$AllUsers,
    [switch]$RestartExplorer
)

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

function Set-BinaryRegistryValue {
    param (
        [string]$Hive,
        [string]$SubKey,
        [string]$ValueName,
        [bool]  $EnableAutoHide
    )

    $psPath = if ($Hive -match ':$') { "$Hive\$SubKey" }
              else { "Registry::$Hive\$SubKey" }

    if (-not (Test-Path $psPath)) {
        Write-Warning "Registry path not found: $psPath"
        return
    }

    try {
        switch -regex ($Hive) {
            '^HKCU:$' { $root = [Microsoft.Win32.Registry]::CurrentUser }
            '^HKLM:$' { $root = [Microsoft.Win32.Registry]::LocalMachine }
            '^HKEY_USERS\\(.+)$' {
                $sid  = $Matches[1]
                $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                    [Microsoft.Win32.RegistryHive]::Users,
                    [Microsoft.Win32.RegistryView]::Default
                ).OpenSubKey($sid, $true)
            }
            default {
                Write-Warning "Unsupported hive: $Hive"
                return
            }
        }

        $key = $root.OpenSubKey($SubKey, $true)
        if (-not $key) {
            Write-Warning "Cannot open subkey $SubKey under $Hive"
            return
        }

        $bytes = $key.GetValue($ValueName)
        if (-not $bytes -or $bytes.Length -lt 9) {
            Write-Warning "Invalid data in $psPath"
            $key.Close()
            return
        }

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

        # Verification
        $actual = (Get-ItemProperty -Path $psPath -Name $ValueName).$ValueName[8]
        if ($actual -eq $bytes[8]) {
            Write-Host "Verification OK: byte[8] = $actual" -ForegroundColor Green
        } else {
            Write-Warning "Verification FAILED: byte[8] = $actual (expected $($bytes[8]))"
        }

    } catch {
        Write-Warning "Error writing to ${Hive}: $_"
    }
}

# Configuration
$subKey         = "Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
$valueName      = "Settings"
$enableAutoHide = -not $Revert

# Elevate if needed
if ($AllUsers -and -not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan
    $scriptArgs = @()
    if ($Revert)          { $scriptArgs += "-Revert" }
    if ($RestartExplorer) { $scriptArgs += "-RestartExplorer" }
    $scriptArgs += "-AllUsers"

    $scriptPath = $MyInvocation.MyCommand.Path
    $cmd        = "& `"$scriptPath`" $($scriptArgs -join ' '); Start-Sleep -Seconds 6"

    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-Command", $cmd
    )
    exit
}

if ($AllUsers) {
    # Only include real user profiles under C:\Users
    $profiles = Get-ChildItem HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList |
        Where-Object {
            $path = (Get-ItemProperty $_.PSPath).ProfileImagePath
            $path -and ($path -like "*\Users\*")
        }

    foreach ($p in $profiles) {
        $sid         = $p.PSChildName
        $profilePath = (Get-ItemProperty -Path $p.PSPath).ProfileImagePath
        $ntUserDat   = Join-Path $profilePath 'NTUSER.DAT'
        $tempHive    = "TempHive_$sid"

        if (-not (Test-Path $ntUserDat)) {
            Write-Warning "NTUSER.DAT not found for SID $sid; skipping"
            continue
        }

        Write-Host "Loading hive for SID $sid..."
        & reg.exe load "HKU\$tempHive" $ntUserDat

        try {
            Set-BinaryRegistryValue -Hive "HKEY_USERS\$tempHive" -SubKey $subKey `
                -ValueName $valueName -EnableAutoHide:$enableAutoHide
        } finally {
            Write-Host "Unloading hive for SID $sid..."
            & reg.exe unload "HKU\$tempHive"
        }
    }
} else {
    # Single-user
    Set-BinaryRegistryValue -Hive "HKCU:" -SubKey $subKey `
        -ValueName $valueName -EnableAutoHide:$enableAutoHide
}

# Restart Explorer or prompt
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log off and log back in for changes to take effect." -ForegroundColor Cyan
}
