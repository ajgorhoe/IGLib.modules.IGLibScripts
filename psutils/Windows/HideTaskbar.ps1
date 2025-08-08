<#
.SYNOPSIS
    Toggles Windows taskbar auto-hide via the AutoHideTaskbar registry setting.

.DESCRIPTION
    Sets or clears the AutoHideTaskbar DWORD under:
      HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced
    to enable/disable the "Automatically hide the taskbar" feature.
    Supports:
      -Revert         : disables auto-hide
      -AllUsers       : applies to all user profiles (requires elevation)
      -RestartExplorer: restarts explorer.exe to apply immediately
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

function Set-AutoHideTaskbar {
    param (
        [string]$Hive,
        [bool]  $Enable
    )

    $valueName = "AutoHideTaskbar"
    $desired   = if ($Enable) { 1 } else { 0 }

    if ($Hive -match ':$') {
        # PSDrive hive (HKCU: or HKLM:)
        $psPath = "$Hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    } else {
        # Literal HKEY_USERS\<sid>
        $psPath = "Registry::$Hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    }

    if (-not (Test-Path $psPath)) {
        Write-Warning "Registry path not found: $psPath"
        return
    }

    try {
        if (-not (Get-ItemProperty -Path $psPath -Name $valueName -ErrorAction SilentlyContinue)) {
            New-ItemProperty -Path $psPath -Name $valueName -PropertyType DWord -Value $desired -Force | Out-Null
        } else {
            Set-ItemProperty -Path $psPath -Name $valueName -Value $desired
        }
        Write-Host "Set AutoHideTaskbar=$desired in $psPath"

        # Verification
        $actual = (Get-ItemProperty -Path $psPath -Name $valueName).$valueName
        if ($actual -eq $desired) {
            Write-Host "Verification successful: AutoHideTaskbar = $actual" -ForegroundColor Green
        } else {
            Write-Warning "Verification failed: AutoHideTaskbar = $actual (expected $desired)"
        }
    }
    catch {
        Write-Warning "Failed to set AutoHideTaskbar in ${Hive}: $_"
    }
}

# Determine desired state
$enable = -not $Revert

# Elevation for AllUsers
if ($AllUsers -and -not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching as administrator..."
    $script = $MyInvocation.MyCommand.Path
    $args   = @()
    if ($Revert)          { $args += "-Revert" }
    if ($RestartExplorer) { $args += "-RestartExplorer" }
    $args += "-AllUsers"

    # Build and invoke elevated process
    $elevArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script
    ) + $args

    Start-Process powershell.exe -Verb RunAs -ArgumentList $elevArgs
    exit
}

# Apply change
if ($AllUsers) {
    $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
                Where-Object { (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*" }

    foreach ($p in $profiles) {
        $sid  = $p.PSChildName
        $hive = "HKEY_USERS\$sid"
        $keyPath = "Registry::$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $keyPath) {
            Set-AutoHideTaskbar -Hive $hive -Enable $enable
        } else {
            Write-Warning "User hive not loaded for SID ${sid} - skipping"
        }
    }
} else {
    Set-AutoHideTaskbar -Hive "HKCU:" -Enable $enable
}

# Restart Explorer if requested
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log out/in for changes to take effect." -ForegroundColor Cyan
}
