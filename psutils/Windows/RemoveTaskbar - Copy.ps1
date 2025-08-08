<#
.SYNOPSIS
    Attempts to hide the Windows taskbar by modifying the StuckRects3 registry key.

.DESCRIPTION
    This script modifies the binary "Settings" value in the "StuckRects3" 
    registry key to set or clear the auto-hide flag for the taskbar. Due to 
    modern Windows protections, this value may be ignored or overwritten by 
    Explorer.
    WARNING: 
    According to some sources, this should remove the taskbar rather than
    activate its auto-hide feature. See for example this post:
    https://learn.microsoft.com/en-us/answers/questions/1040472/no-taskbar-on-window?orderBy=Newest
    Before Windows Explorer is restarted, setting or unsetting the flag in
    Windows Registry does not have effect. However, after restarting, the
    Explorer seems to set the registry value back to its default (2, while
    10 should cause removing/hiding the taskbar). The value can be verified by
    evaluating the following expression in PowerShell:
    (Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" -Name Settings).Settings[8]

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
        [bool]$EnableAutoHide
    )

    # Build PSDrive-style path for Test-Path/Get-ItemProperty
    $psPath = "$Hive\$SubKey"

    if (-not (Test-Path $psPath)) {
        Write-Warning "Registry path $psPath not found. Skipping..."
        return
    }

    try {
        # Open base key
        if ($Hive -eq "HKCU:") {
            $root = [Microsoft.Win32.Registry]::CurrentUser
        } elseif ($Hive -eq "HKLM:") {
            $root = [Microsoft.Win32.Registry]::LocalMachine
        } elseif ($Hive -like "HKEY_USERS\*") {
            # e.g. Hive = "HKEY_USERS\S-1-5-21-..."
            $sid = $Hive.Substring(11)
            $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                [Microsoft.Win32.RegistryHive]::Users,
                [Microsoft.Win32.RegistryView]::Default
            )
            $root = $root.OpenSubKey($sid, $true)
        } else {
            Write-Warning "Unsupported hive: $Hive"
            return
        }

        # Open the subkey for write
        $key = $root.OpenSubKey($SubKey, $true)
        if (-not $key) {
            Write-Warning "Could not open subkey $SubKey under $Hive"
            return
        }

        # Read existing binary value
        $bytes = $key.GetValue($ValueName)
        if (-not $bytes -or $bytes.Length -lt 9) {
            Write-Warning "Unexpected Settings format under $psPath"
            $key.Close(); return
        }

        # Modify byte 8
        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08
            Write-Host "Set bit to ENABLE Auto-hide, new byte[8] = $($bytes[8])"
        } else {
            $bytes[8] = $bytes[8] -band 0xF7
            Write-Host "Set bit to DISABLE Auto-hide, new byte[8] = $($bytes[8])"
        }

        # Write back
        $key.SetValue($ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
        $key.Close()
        Write-Host "Updated $psPath\$ValueName successfully."

        # Verification
        try {
            $verified = (Get-ItemProperty -Path $psPath -Name $ValueName).$ValueName
            $actual = $verified[8]
            if ($actual -eq $bytes[8]) {
                Write-Host "Verification successful: byte[8] = $actual (matches expected)" -ForegroundColor Green
            } else {
                Write-Warning "Verification failed: byte[8] = $actual (expected $($bytes[8])) - value may have been overwritten."
            }
        } catch {
            Write-Warning "Could not verify registry value after write: $_"
        }
    }
    catch {
        Write-Warning "Failed to apply taskbar auto-hide to ${Hive}: $_"
    }
}

# Main
$subKey    = "Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
$valueName = "Settings"
$enable    = -not $Revert

if ($AllUsers) {
    if (-not (Test-IsAdministrator)) {
        Write-Host "Elevation required. Relaunching as administrator..."
        $script = $MyInvocation.MyCommand.Path
        $args = @()
        if ($Revert)          { $args += "-Revert" }
        if ($RestartExplorer) { $args += "-RestartExplorer" }
        $args += "-AllUsers"
        Start-Process powershell.exe -Verb RunAs -ArgumentList @(
            "-NoProfile","-ExecutionPolicy","Bypass","-File","`"$script`"",$args
        )
        exit
    }

    # Loop all user SIDs
    $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
                Where-Object { (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*" }

    foreach ($p in $profiles) {
        $sid  = $p.PSChildName
        $hive = "HKEY_USERS\$sid"
        $psPath = "Registry::$hive\$subKey"
        if (Test-Path $psPath) {
            Set-BinaryRegistryValue -Hive "HKEY_USERS\$sid" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enable
        } else {
            Write-Warning "User hive not loaded for SID ${sid} - skipping"
        }
    }
} else {
    Set-BinaryRegistryValue -Hive "HKCU:" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enable
}

if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log out/in for the changes to take effect." -ForegroundColor Cyan
}
