<#
.SYNOPSIS
    Sets the taskbar icon size in Windows 11.

.DESCRIPTION
    Changes the taskbar size by modifying the TaskbarSi registry value.
    Default behavior sets the taskbar to Small size.
    Use -Revert to reset to Medium (default) size.
    Use -Size to explicitly specify Small, Medium, or Large.
    -AllUsers applies the setting to all user profiles (requires elevation).
    -RestartExplorer restarts the Explorer process after changes.

.PARAMETER Revert
    Reverts taskbar size to Medium.

.PARAMETER Size
    Overrides default/Revert and sets taskbar size to a specific value.

.PARAMETER RestartExplorer
    Restarts Explorer after making changes.

.PARAMETER AllUsers
    Applies the setting to all users (requires admin rights).
#>

param (
    [switch]$Revert,
    [ValidateSet("Small", "Medium", "Large")]
    [string]$Size,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

# Mapping descriptive size to registry value
$sizeMap = @{
    Small  = 0
    Medium = 1
    Large  = 2
}

# Determine target size
if ($Size) {
    $targetSize = $Size
} elseif ($Revert) {
    $targetSize = "Medium"
} else {
    $targetSize = "Small"
}

$regValue = $sizeMap[$targetSize]

# Restart Explorer function
function Restart-Explorer {
    Write-Host "Restarting Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
    Start-Process explorer
    Write-Host "Explorer restarted." -ForegroundColor Green
}

# Apply setting to a single registry path
function Set-TaskbarSize {
    param (
        [string]$BasePath
    )

    $regPath = "$BasePath\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

    try {
        if (-not (Test-Path $regPath)) {
            Write-Warning "Skipping user: Cannot access registry path `${regPath}`"
            return
        }

        Set-ItemProperty -Path $regPath -Name "TaskbarSi" -Value $regValue -Type DWord -Force
        Write-Host "Set taskbar size to '$targetSize' at: $regPath" -ForegroundColor Green
    }
    catch {
        Write-Warning "Failed to apply taskbar size to `${regPath}`: $_"
    }
}

# Main logic
if ($AllUsers) {
    # Check elevation
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan

		# Elevation relaunch
		$scriptArgs = @()
		if ($AllUsers)         { $scriptArgs += "-AllUsers" }
		if ($Revert)           { $scriptArgs += "-Revert" }
		if ($RestartExplorer)  { $scriptArgs += "-RestartExplorer" }
		if ($Size)             { $scriptArgs += "-Size `"$Size`"" }

		$joinedArgs = $scriptArgs -join ' '
		$scriptPathQuoted = '"' + $PSCommandPath + '"'
		$command = "`"& $scriptPathQuoted $joinedArgs; Start-Sleep -Seconds 3`""

		Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command -Verb RunAs
		exit
		
    }

    # Elevated: loop over all loaded user profiles
    Write-Host "Applying taskbar size to all users..." -ForegroundColor Cyan

    $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
        Where-Object {
            (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*"
        }

    foreach ($profile in $profiles) {
        $sid = $profile.PSChildName
        $userHive = "Registry::HKEY_USERS\$sid"

        if (Test-Path "$userHive\Software") {
            Set-TaskbarSize -BasePath $userHive
        } else {
            Write-Warning "User hive not loaded for SID $sid — skipping"
        }
    }
} else {
    # Current user only
    Write-Host "Applying taskbar size to current user..." -ForegroundColor Cyan
    Set-TaskbarSize -BasePath "HKCU:"
}

# Restart Explorer if requested
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "`nYou may need to restart Explorer or log off/on to see the changes." -ForegroundColor Cyan
}
