<#
.SYNOPSIS
    Attempts to hide the Windows taskbar by modifying the StuckRects3 registry key.

.DESCRIPTION
    This script modifies the binary "Settings" value in the "StuckRects3" registry key to set or clear
    the auto-hide flag for the taskbar. Due to modern Windows protections, this value may be ignored or
    overwritten by Explorer.

.PARAMETER Revert
    Reverts the taskbar setting to default (no auto-hide attempt).

.PARAMETER AllUsers
    Attempts to apply the setting for all users (requires elevation).

.PARAMETER RestartExplorer
    Restarts Windows Explorer after making changes.

.EXAMPLE
    .\RemoveTaskbar.ps1 -RestartExplorer

.NOTES
    This script is intended for experimental purposes and may not persist changes in modern Windows versions.
#>

param (
    [switch]$Revert,
    [switch]$AllUsers,
    [switch]$RestartExplorer
)

function Test-IsAdministrator {
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object System.Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Set-BinaryRegistryValue {
    param (
        [string]$Hive,
        [string]$SubKey,
        [string]$ValueName,
        [bool]$EnableAutoHide
    )

    try {
        $regPath = Join-Path $Hive $SubKey

        if (-not (Test-Path $regPath)) {
            Write-Warning "Registry path $regPath not found. Skipping..."
            return
        }

        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($SubKey, $true)
        if ($Hive -eq "HKLM:") {
            $key = [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey($SubKey, $true)
        }

        $bytes = $key.GetValue($ValueName)

        if ($null -eq $bytes -or $bytes.Length -lt 9) {
            Write-Warning "Settings value not found or invalid in $regPath"
            return
        }

        # Modify byte at index 8: bit 3 controls auto-hide
        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08
            Write-Host "Set bit to ENABLE Auto-hide, new byte[8] = $($bytes[8])"
        } else {
            $bytes[8] = $bytes[8] -band 0xF7
            Write-Host "Set bit to DISABLE Auto-hide, new byte[8] = $($bytes[8])"
        }

        $key.SetValue($ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
        $key.Close()

        Write-Host "Updated $regPath\$ValueName successfully."
        
        # === Verification Step ===
        try {
            $verifiedBytes = (Get-ItemProperty -Path $regPath -Name $ValueName).$ValueName
            $actual = $verifiedBytes[8]

            if ($actual -eq $bytes[8]) {
                Write-Host "Verification successful: byte[8] = $actual (matches expected)" -ForegroundColor Green
            } else {
                Write-Warning "Verification failed: byte[8] = $actual (expected $($bytes[8])) — value may have been overwritten."
            }
        } catch {
            Write-Warning "Could not verify registry value after write: $_"
        }

    } catch {
        Write-Warning "Failed to apply taskbar auto-hide to ${Hive}: $_"
    }
}

function Restart-Explorer {
    Write-Host "Restarting Windows Explorer..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

# Main Logic
$subKey = "Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
$valueName = "Settings"
$enableAutoHide = -not $Revert

if ($AllUsers) {
    if (-not (Test-IsAdministrator)) {
        Write-Host "Elevation required. Relaunching with administrative privileges..."
        $scriptPath = $MyInvocation.MyCommand.Path
        $argList = @()
        if ($Revert) { $argList += "-Revert" }
        if ($RestartExplorer) { $argList += "-RestartExplorer" }
        $argList += "-AllUsers"

        Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "`"$scriptPath`"", $argList
        exit
    }

    $profileList = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    foreach ($profile in $profileList) {
        $sid = $profile.PSChildName
        try {
            $profilePath = $profile.GetValue("ProfileImagePath")
            if (-not $profilePath) {
                Write-Warning "User hive not loaded for SID $sid - skipping"
                continue
            }
            $userHive = "Registry::HKEY_USERS\$sid\$($subKey)"
            Set-BinaryRegistryValue -Hive "HKU:\$sid" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
        } catch {
            Write-Warning "Failed to apply setting for SID ${sid}: $_"
        }
    }
} else {
    Set-BinaryRegistryValue -Hive "HKCU:" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
}

if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log out/in for the changes to take effect."
}
