<#
.SYNOPSIS
    Sets the desktop icon size in Windows.

.DESCRIPTION
    Changes the desktop icon size via registry.
    Default behavior sets to Small (16).
    Use -Revert to reset to Medium (32).
    Use -Size to specify Small, Medium, Large, or ExtraLarge.
    -AllUsers applies the setting to all user profiles (requires elevation).
    -RestartExplorer restarts the Explorer process after changes.

.PARAMETER Revert
    Reverts icon size to Medium (32).

.PARAMETER Size
    Explicitly set to Small, Medium, Large, or ExtraLarge.

.PARAMETER RestartExplorer
    Restart Explorer to apply changes.

.PARAMETER AllUsers
    Apply changes to all users (requires admin rights).
#>

param (
    [switch]$Revert,
    [ValidateSet("Small", "Medium", "Large", "ExtraLarge")]
    [string]$Size,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

# Map sizes to values
$sizeMap = @{
    Small      = 16
    Medium     = 32
    Large      = 48
    ExtraLarge = 64
}

# Determine desired value
if ($Size) {
    $targetSize = $Size
} elseif ($Revert) {
    $targetSize = "Medium"
} else {
    $targetSize = "Small"
}

$regValue = $sizeMap[$targetSize]

# Restart Explorer
function Restart-Explorer {
    Write-Host "Restarting Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
    Start-Process explorer
    Write-Host "Explorer restarted." -ForegroundColor Green
}

# Apply setting
function Set-DesktopIconSize {
    param (
        [string]$BasePath
    )

    $osVersion = [System.Environment]::OSVersion.Version
    if ($osVersion.Major -eq 10 -and $osVersion.Build -ge 26000) {
        Write-Warning "This version of Windows (Build $($osVersion.Build)) may handle desktop icon sizing differently. Proceeding anyway..."
    }

    $regPath = "$BasePath\Software\Microsoft\Windows\Shell\Bags\1\Desktop"

    try {
        if (-not (Test-Path $regPath)) {
            New-Item -Path $regPath -Force | Out-Null
        }

        Set-ItemProperty -Path $regPath -Name "IconSize" -Value $regValue -Type DWord -Force
        Write-Host "Set desktop icon size to '$targetSize' at: $regPath" -ForegroundColor Green
        Write-Host "    regValue: $regValue"
    }
    catch {
        Write-Warning "Failed to set icon size at $regPath: $_"
    }
}

# Handle elevation for -AllUsers
if ($AllUsers) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (-not $isAdmin) {
        Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan

        $scriptArgs = @()
        if ($AllUsers)         { $scriptArgs += "-AllUsers" }
        if ($Revert)           { $scriptArgs += "-Revert" }
        if ($RestartExplorer)  { $scriptArgs += "-RestartExplorer" }
        if ($Size)             { $scriptArgs += "-Size `"$Size`"" }

        $joinedArgs = $scriptArgs -join ' '
        $quotedScriptPath = '"' + $PSCommandPath + '"'
        $fullCommand = "& $quotedScriptPath $joinedArgs; Start-Sleep -Seconds 3"

        Start-Process powershell.exe -ArgumentList @(
            "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-Command", "`"$fullCommand`""
        ) -Verb RunAs

        exit
    }

    Write-Host "Applying desktop icon size to all users..." -ForegroundColor Cyan

    $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
        Where-Object {
            (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*"
        }

    foreach ($profile in $profiles) {
        $sid = $profile.PSChildName
        $userHive = "Registry::HKEY_USERS\$sid"

        if (Test-Path "$userHive\Software") {
            Set-DesktopIconSize -BasePath $userHive
        } else {
            Write-Warning "User hive not loaded for SID $sid - skipping"
        }
    }
}
else {
    Write-Host "Applying desktop icon size to current user..." -ForegroundColor Cyan
    Set-DesktopIconSize -BasePath "HKCU:"
}

# Restart if requested
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host ""
    Write-Host "You may need to restart Explorer or log off/on to see the changes." -ForegroundColor Cyan
}
