<#
.SYNOPSIS
    Adds or removes "Text Document" from the "New" context menu in File Explorer.

.DESCRIPTION
    This script adds a missing "Text Document" (.txt) entry to the "New" submenu of File Explorer's context menu.
    It modifies the .txt file association under the registry to ensure the entry appears.
    You can use the -Revert switch to remove the entry.
    The -AllUsers switch applies changes for all user profiles (requires elevation).
    The -RestartExplorer switch restarts the Explorer process to apply the change immediately.

.PARAMETER Revert
    Removes the "Text Document" entry from the New context menu.

.PARAMETER RestartExplorer
    Restarts Explorer after making changes.

.PARAMETER AllUsers
    Applies the change to all users (requires elevation).

.EXAMPLE
    .\AddNewTextFileToContextMenu.ps1
    Adds "Text Document" to the current user's New menu.

.EXAMPLE
    .\AddNewTextFileToContextMenu.ps1 -Revert -RestartExplorer
    Removes the entry and restarts Explorer.

.EXAMPLE
    .\AddNewTextFileToContextMenu.ps1 -AllUsers
    Adds the entry for all users (elevation required).
#>

param (
    [switch]$Revert,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

# Restart Explorer function
function Restart-Explorer {
    Write-Host "Restarting Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
    Start-Process explorer
    Write-Host "Explorer restarted." -ForegroundColor Green
}

# Registry modification function
function Set-NewTextFileRegistry {
    param (
        [string]$BasePath,
        [switch]$Revert
    )

    $keyPath = "$BasePath\Software\Classes\.txt\ShellNew"

    if ($Revert) {
        # Revert: remove the ShellNew key
        if (Test-Path $keyPath) {
            Remove-Item -Path $keyPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Removed 'New Text Document' at: $keyPath" -ForegroundColor Yellow
        }
    } else {
        # Ensure ShellNew key exists and has appropriate values
        if (-not (Test-Path $keyPath)) {
            New-Item -Path $keyPath -Force | Out-Null
        }

        # Add NullFile value (no default content needed)
        New-ItemProperty -Path $keyPath -Name "NullFile" -PropertyType String -Value "" -Force | Out-Null
        Write-Host "Added 'New Text Document' at: $keyPath" -ForegroundColor Green
    }
}

# If -AllUsers is set, handle elevation
if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan

        # Build argument string
        $scriptArgs = @()
        if ($AllUsers)         { $scriptArgs += "-AllUsers" }
        if ($Revert)           { $scriptArgs += "-Revert" }
        if ($RestartExplorer)  { $scriptArgs += "-RestartExplorer" }

        $joinedArgs = $scriptArgs -join ' '
        $escapedScriptPath = $PSCommandPath.Replace('"', '""')
        $command = "& `"$escapedScriptPath`" $joinedArgs; Start-Sleep -Seconds 3"

        Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command -Verb RunAs
        exit
    }

    # Elevated: apply change for all user profiles
    Write-Host "Applying to all user profiles..." -ForegroundColor Cyan

    $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
        Where-Object {
            (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*"
        }

    foreach ($profile in $profiles) {
        $sid = $profile.PSChildName
        $userHive = "Registry::HKEY_USERS\$sid"

        try {
            Set-NewTextFileRegistry -BasePath $userHive -Revert:$Revert
        } catch {
            Write-Warning "Failed to apply setting to SID: $sid"
        }
    }
} else {
    # Apply to current user
    Write-Host "Applying to current user..." -ForegroundColor Cyan
    Set-NewTextFileRegistry -BasePath "HKCU:" -Revert:$Revert
}

# Restart Explorer if requested
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "`nYou may need to restart Explorer or log off/log on to see changes." -ForegroundColor Cyan
}
