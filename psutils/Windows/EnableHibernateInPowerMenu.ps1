<#
.SYNOPSIS
    Enables or disables the Hibernate option in the Power menu.

.DESCRIPTION
    This script enables Hibernate in the Windows Power menu by using powercfg and ensuring
    system registry settings are correctly set. It supports reverting, restarting Explorer,
    and can be safely deployed on any edition of Windows.

.PARAMETER Revert
    Disables Hibernate and removes it from the Power menu.

.PARAMETER RestartExplorer
    Restarts Explorer to reflect menu changes immediately.

.PARAMETER AllUsers
    Reserved for consistency with other scripts. This script always runs system-wide and requires elevation.

.EXAMPLE
    .\EnableHibernateInPowerMenu.ps1
    Enables Hibernate.

.EXAMPLE
    .\EnableHibernateInPowerMenu.ps1 -Revert -RestartExplorer
    Disables Hibernate and restarts Explorer.

.EXAMPLE
    .\EnableHibernateInPowerMenu.ps1 -AllUsers
    Enables Hibernate (elevation always required).
#>

param (
    [switch]$Revert,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

# Check for elevation
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan

    # Build arguments for elevated relaunch
    $args = @()
    if ($AllUsers)         { $args += "-AllUsers" }
    if ($Revert)           { $args += "-Revert" }
    if ($RestartExplorer)  { $args += "-RestartExplorer" }

    $joinedArgs = $args -join ' '
    $escapedScriptPath = $PSCommandPath.Replace('"', '""')
    $command = "& `"$escapedScriptPath`" $joinedArgs; Start-Sleep -Seconds 3"

    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command -Verb RunAs
    exit
}

# Restart Explorer function
function Restart-Explorer {
    Write-Host "Restarting Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
    Start-Process explorer
    Write-Host "Explorer restarted." -ForegroundColor Green
}

# Hibernate toggle function
function Set-HibernateState {
    param (
        [switch]$Revert
    )

    if ($Revert) {
        Write-Host "Disabling hibernation..." -ForegroundColor Yellow
        powercfg /hibernate off | Out-Null

        # Remove ShowHibernateOption override
        Remove-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings" -Name "ShowHibernateOption" -ErrorAction SilentlyContinue

        Write-Host "Hibernation has been disabled." -ForegroundColor Yellow
    } else {
        Write-Host "Enabling hibernation..." -ForegroundColor Green
        powercfg /hibernate on | Out-Null

        # Ensure the Explorer flyout menu shows Hibernate
        $flyoutKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FlyoutMenuSettings"
        if (-not (Test-Path $flyoutKey)) {
            New-Item -Path $flyoutKey -Force | Out-Null
        }

        Set-ItemProperty -Path $flyoutKey -Name "ShowHibernateOption" -Value 1 -Type DWord -Force

        Write-Host "Hibernation has been enabled and set to appear in Power menu." -ForegroundColor Green
    }
}


# Apply setting
Set-HibernateState -Revert:$Revert

# Restart Explorer if requested
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "`nYou may need to restart Explorer or reboot to see changes in the Power menu." -ForegroundColor Cyan
}
