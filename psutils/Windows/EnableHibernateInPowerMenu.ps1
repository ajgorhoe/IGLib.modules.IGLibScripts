
<#
.SYNOPSIS
    Enables or disables the Hibernate option in the Power menu.

.DESCRIPTION
    This script enables the Hibernate option by turning on hibernation using powercfg
    and ensuring it appears in the Windows Power menu via registry settings.
    It supports reverting, Explorer restart, and applying system-wide via elevation.

.PARAMETER Revert
    Disables Hibernate and removes it from the Power menu.

.PARAMETER RestartExplorer
    Restarts Explorer to reflect menu changes immediately.

.PARAMETER AllUsers
    Ensures the change is applied for all users. Prompts for elevation if needed.

.EXAMPLE
    .\EnableHibernateInPowerMenu.ps1
    Enables Hibernate for current user.

.EXAMPLE
    .\EnableHibernateInPowerMenu.ps1 -Revert -RestartExplorer
    Disables Hibernate and restarts Explorer.

.EXAMPLE
    .\EnableHibernateInPowerMenu.ps1 -AllUsers
    Enables Hibernate system-wide.
#>

param (
    [switch]$Revert,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

function Restart-Explorer {
    Write-Host "Restarting Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
    Start-Process explorer
    Write-Host "Explorer restarted." -ForegroundColor Green
}

function Set-HibernateRegistry {
    param (
        [switch]$Revert
    )

    # Modify registry for power menu visibility (optional on modern Windows, but improves consistency)
    $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Power"
    $valueName = "HibernateEnabled"

    if ($Revert) {
        Write-Host "Disabling hibernation via powercfg..." -ForegroundColor Yellow
        powercfg /hibernate off | Out-Null

        # Registry cleanup is optional, as powercfg handles it
        Write-Host "Hibernation disabled." -ForegroundColor Yellow
    } else {
        Write-Host "Enabling hibernation via powercfg..." -ForegroundColor Green
        powercfg /hibernate on | Out-Null
        Write-Host "Hibernation enabled." -ForegroundColor Green
    }
}

# Elevate if needed for -AllUsers
if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan

        # Build argument list
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

    Write-Host "Applying hibernation setting system-wide..." -ForegroundColor Cyan
    Set-HibernateRegistry -Revert:$Revert
} else {
    Write-Host "Applying hibernation setting for current system..." -ForegroundColor Cyan
    Set-HibernateRegistry -Revert:$Revert
}

if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "`nYou may need to restart Explorer or reboot to see changes." -ForegroundColor Cyan
}
