<#
.SYNOPSIS
    Enables or disables full classic context menus in Windows 11.

.DESCRIPTION
    This script modifies the registry to force Windows 11 to show full right-click context menus
    instead of the simplified version that requires "Show more options".

    By default, the change is applied to the current user only.
    Use the -AllUsers switch to apply it to all existing users (requires Administrator privileges).
    The -RestartExplorer switch applies the changes immediately.

.PARAMETER Revert
    Reverts to the default "Show more options" behavior.

.PARAMETER RestartExplorer
    Restarts the Explorer process after making changes to apply them immediately.

.PARAMETER AllUsers
    Applies the registry change to all existing users on the system (requires elevation).
    If not elevated, a prompt is shown. If elevation is denied, a warning is issued and the change is applied to the current user only.

.EXAMPLE
    .\ShowFullContextMenus.ps1
    Enables full context menus for current user.

.EXAMPLE
    .\ShowFullContextMenus.ps1 -Revert -RestartExplorer
    Reverts to default behavior and restarts Explorer.

.EXAMPLE
    .\ShowFullContextMenus.ps1 -AllUsers
    Enables full context menus for all users (requires admin).

.EXAMPLE
    .\ShowFullContextMenus.ps1 -Revert -AllUsers -RestartExplorer
    Reverts to default behavior for all users and restarts Explorer.
#>

param (
    [switch]$Revert,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

# Function to restart Explorer
function Restart-Explorer {
    Write-Host "Restarting Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
    Start-Process explorer
    Write-Host "Explorer restarted." -ForegroundColor Green
}

# Function to apply registry change to a given registry path
function Set-ContextMenuRegistry {
    param (
        [string]$BasePath,
        [switch]$Revert
    )

    $regPath = "$BasePath\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
    $subKey = "$regPath\InprocServer32"

    if ($Revert) {
        # Remove the registry key to revert the behavior
        if (Test-Path $regPath) {
            Remove-Item -Path $regPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "Reverted context menu setting at: $regPath" -ForegroundColor Yellow
        }
    } else {
        # Create and set the registry key to enable full context menus
        if (-not (Test-Path $subKey)) {
            New-Item -Path $subKey -Force | Out-Null
        }
        Set-ItemProperty -Path $subKey -Name "(Default)" -Value "" -Force
        Write-Host "Enabled full context menu at: $subKey" -ForegroundColor Green
    }
}

# Check for elevation if -AllUsers is specified
if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan

		# Build list of script arguments
		$scriptArgs = @()
		if ($AllUsers)         { $scriptArgs += "-AllUsers" }
		if ($Revert)           { $scriptArgs += "-Revert" }
		if ($RestartExplorer)  { $scriptArgs += "-RestartExplorer" }

		# Join script arguments into a single string
		$joinedArgs = $scriptArgs -join ' '

		# Escape the script path
		$escapedScriptPath = $PSCommandPath.Replace('"', '""')

		# Build the command to run as Administrator, with Start-Sleep at the end
		$command = "& `"$escapedScriptPath`" $joinedArgs; Start-Sleep -Seconds 6"

		# Start elevated PowerShell session
		Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command -Verb RunAs
		exit
    }

    # Elevated: Apply setting to all user profiles
    Write-Host "Applying changes for all users..." -ForegroundColor Cyan

    # Get all user profiles (excluding system)
    $profiles = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' |
        Where-Object {
            (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*"
        }

    foreach ($profile in $profiles) {
        $sid = $profile.PSChildName
        $userHive = "Registry::HKEY_USERS\$sid"

        try {
            Set-ContextMenuRegistry -BasePath $userHive -Revert:$Revert
        } catch {
            Write-Warning "Failed to apply setting to SID: $sid"
        }
    }
} else {
    # Apply to current user only
    Write-Host "Applying changes for current user..." -ForegroundColor Cyan
    Set-ContextMenuRegistry -BasePath "HKCU:" -Revert:$Revert
}

# Restart Explorer if requested
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "`nYou may need to restart the Explorer process or reboot your system for changes to take effect." -ForegroundColor Cyan
}
