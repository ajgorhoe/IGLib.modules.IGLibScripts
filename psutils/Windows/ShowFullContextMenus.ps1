#!/usr/bin/env pwsh

<#
.SYNOPSIS
    Enables or disables full classic context menus in Windows 11.

.DESCRIPTION
    This script modifies the registry to force Windows 11 to show full right-click context menus
    instead of the simplified version that requires "Show more options".
    Use the -Revert switch to restore the default behavior.
    Use the -RestartExplorer switch to automatically restart the Explorer process.

.PARAMETER Revert
    Use this switch to revert to default behavior (partial context menus).

.PARAMETER RestartExplorer
    Automatically restarts the Explorer process after making registry changes.

.EXAMPLE
    .\ShowFullContextMenus.ps1
    Enables full context menus.

.EXAMPLE
    .\ShowFullContextMenus.ps1 -Revert
    Reverts to the default "Show more options" behavior.

.EXAMPLE
    .\ShowFullContextMenus.ps1 -RestartExplorer
    Enables full context menus and restarts Explorer.

.EXAMPLE
    .\ShowFullContextMenus.ps1 -Revert -RestartExplorer
    Reverts to default and restarts Explorer.
#>

param (
    [switch]$Revert,
    [switch]$RestartExplorer
)

# Registry path and value
$regPath = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
$subKey = "InprocServer32"

function Restart-Explorer {
    Write-Host "Restarting Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
    Start-Process explorer
    Write-Host "Explorer restarted." -ForegroundColor Green
}

try {
    if ($Revert) {
        # Revert to default: remove the key
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force
            Write-Host "Successfully reverted to default context menu behavior." -ForegroundColor Yellow
        } else {
            Write-Host "Registry key not found. Nothing to revert." -ForegroundColor DarkYellow
        }
    } else {
        # Enable full context menus
        if (-not (Test-Path "$regPath\$subKey")) {
            New-Item -Path "$regPath\$subKey" -Force | Out-Null
        }

        # Set default value to empty string
        Set-ItemProperty -Path "$regPath\$subKey" -Name "(Default)" -Value "" -Force
        Write-Host "Full context menus have been enabled." -ForegroundColor Green
    }

    if ($RestartExplorer) {
        Restart-Explorer
    } else {
        Write-Host "`nYou must restart the Explorer process or reboot your system for changes to take effect." -ForegroundColor Cyan
    }
}
catch {
    Write-Error "An error occurred: $_"
}

