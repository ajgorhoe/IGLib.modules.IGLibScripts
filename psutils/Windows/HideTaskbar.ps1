param (
    [switch]$Revert,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

function Is-Administrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Explorer {
    Write-Host "Restarting Windows Explorer..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer
}

function Apply-TaskbarAutoHide {
    param (
        [string]$Hive = "HKCU",
        [bool]$EnableAutoHide
    )

    $regPath = "Registry::$Hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"

    if (-not (Test-Path $regPath)) {
        Write-Warning "Registry path not found: $regPath"
        return
    }

    try {
        $value = Get-ItemProperty -Path $regPath -Name Settings -ErrorAction Stop
        $bytes = $value.Settings

        if ($bytes.Length -lt 8) {
            Write-Warning "Unexpected registry value format in $regPath"
            return
        }

        # Modify byte at index 8: bit 5 controls auto-hide
        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08  # Set bit 3 (auto-hide)
            Write-Warning "Byte set to ENABLE Autohide, value = $bytes[8] "
        } else {
            $bytes[8] = $bytes[8] -band 0xF7  # Clear bit 3
            Write-Warning "Byte set to DISABLE Autohide, value = $bytes[8] "
        }

        Set-ItemProperty -Path $regPath -Name Settings -Value $bytes
        Write-Host "Taskbar auto-hide set to $EnableAutoHide in $Hive"

    } catch {
        Write-Warning "Failed to apply taskbar auto-hide to ${Hive}: $_"
    }
}

# Elevation logic
if ($AllUsers -and -not (Is-Administrator)) {
    Write-Host "Elevation required to apply to all users. Relaunching as administrator..."

    $scriptPath = $MyInvocation.MyCommand.Path
    $escapedArgs = @()
    if ($Revert) { $escapedArgs += "-Revert" }
    if ($RestartExplorer) { $escapedArgs += "-RestartExplorer" }
    $escapedArgs += "-AllUsers"

    $command = "& `"$scriptPath`" $($escapedArgs -join ' '); Start-Sleep -Seconds 5"

    Start-Process powershell.exe -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", $command -Verb RunAs
    exit
}

# Main logic
$enable = -not $Revert

if ($AllUsers) {
    $profileListPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
    $profiles = Get-ChildItem -Path $profileListPath | Where-Object {
        $sid = $_.PSChildName
        $sid -match '^S-1-5-21-' -and
        (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*"
    }

    foreach ($profile in $profiles) {
        $sid = $profile.PSChildName
        $hive = "HKEY_USERS\$sid"

        # Only apply if the user hive is loaded
        if (Test-Path "Registry::$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3") {
            Apply-TaskbarAutoHide -Hive $hive -EnableAutoHide:$enable
        } else {
            Write-Warning "User hive not loaded for SID $sid - skipping"
        }
    }
} else {
    Apply-TaskbarAutoHide -EnableAutoHide:$enable
}

if ($RestartExplorer) {
    Restart-Explorer
}
else {
    Write-Host "You may need to restart Explorer or log out/in for the changes to take effect." -ForegroundColor Cyan
}