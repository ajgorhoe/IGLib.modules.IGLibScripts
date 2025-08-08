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

function Set-BinaryRegistryValue {
    param (
        [string]$Hive,
        [string]$SubKeyPath,
        [string]$ValueName,
        [byte[]]$Value
    )

    $root = switch ($Hive) {
        "HKCU" { [Microsoft.Win32.Registry]::CurrentUser }
        { $_ -like "HKEY_USERS\\*" } {
            $sid = $_.Split("\\")[1]
            [Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::Users, [Microsoft.Win32.RegistryView]::Default).OpenSubKey($sid, $true)
        }
        default {
            Write-Warning "Unsupported registry hive: $Hive"
            return
        }
    }

    try {
        $key = $root.OpenSubKey($SubKeyPath, $true)
        if (-not $key) {
            Write-Warning "Could not open registry path: $Hive\$SubKeyPath"
            return
        }

        $key.SetValue($ValueName, $Value, [Microsoft.Win32.RegistryValueKind]::Binary)
        $key.Close()
        Write-Host "Updated $Hive\$SubKeyPath\$ValueName successfully."
    } catch {
        Write-Warning "Failed to write binary registry value: $_"
    }
}

function Apply-TaskbarAutoHide {
    param (
        [string]$Hive = "HKCU",
        [bool]$EnableAutoHide
    )

    $subKeyPath = "Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
    $regPath = "Registry::$Hive\$subKeyPath"

    if (-not (Test-Path $regPath)) {
        Write-Warning "Registry path not found: $regPath"
        return
    }

    try {
        $value = Get-ItemProperty -Path $regPath -Name Settings -ErrorAction Stop
        $bytes = $value.Settings

        if ($bytes.Length -lt 9) {
            Write-Warning "Unexpected format in $regPath"
            return
        }

        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08
            Write-Host "Set bit to ENABLE Auto-hide, new byte[8] = $($bytes[8])"
        } else {
            $bytes[8] = $bytes[8] -band 0xF7
            Write-Host "Set bit to DISABLE Auto-hide, new byte[8] = $($bytes[8])"
        }

        Set-BinaryRegistryValue -Hive $Hive -SubKeyPath $subKeyPath -ValueName "Settings" -Value $bytes

        Write-Host "Taskbar auto-hide set to $EnableAutoHide in $Hive"
    } catch {
        Write-Warning "Failed to apply taskbar auto-hide to ${Hive}: $_"
    }
}

# Elevation check for -AllUsers
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
        $_.PSChildName -match '^S-1-5-21-' -and
        (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*"
    }

    foreach ($profile in $profiles) {
        $sid = $profile.PSChildName
        $hive = "HKEY_USERS\$sid"
        $subKey = "$hive\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
        if (Test-Path "Registry::$subKey") {
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
} else {
    Write-Host "You may need to restart Explorer or log out/in for the changes to take effect." -ForegroundColor Cyan
}
