<#
.SYNOPSIS
    Attempts to hide the Windows taskbar by patching the StuckRects3 binary registry key.

.DESCRIPTION
    Modifies the byte at index 8 of the "Settings" value in:
      HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3
    to set/clear the auto-hide flag. Verifies immediately afterwards.
    Supports:
      -Revert         : clears the auto-hide bit
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

function Set-BinaryRegistryValue {
    param (
        [string]$Hive,
        [string]$SubKey,
        [string]$ValueName,
        [bool]  $EnableAutoHide
    )

    $psPath = "$Hive\$SubKey"
    if (-not (Test-Path $psPath)) {
        Write-Warning "Registry path $psPath not found. Skipping..."
        return
    }

    try {
        if ($Hive -eq "HKCU:")    { $root = [Microsoft.Win32.Registry]::CurrentUser }
        elseif ($Hive -eq "HKLM:") { $root = [Microsoft.Win32.Registry]::LocalMachine }
        else {
            $sid  = $Hive.Substring(11)
            $root = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                        [Microsoft.Win32.RegistryHive]::Users,
                        [Microsoft.Win32.RegistryView]::Default
                    )
            $root = $root.OpenSubKey($sid, $true)
        }

        $key = $root.OpenSubKey($SubKey, $true)
        if (-not $key) {
            Write-Warning "Could not open subkey $SubKey under $Hive"
            return
        }

        $bytes = $key.GetValue($ValueName)
        if (-not $bytes -or $bytes.Length -lt 9) {
            Write-Warning "Unexpected Settings format at $psPath"
            $key.Close(); return
        }

        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08
            Write-Host "Enabled auto-hide bit: new byte[8] = $($bytes[8])"
        } else {
            $bytes[8] = $bytes[8] -band 0xF7
            Write-Host "Disabled auto-hide bit: new byte[8] = $($bytes[8])"
        }

        $key.SetValue($ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
        $key.Close()
        Write-Host "Updated $psPath\$ValueName successfully."

        $verified = (Get-ItemProperty -Path $psPath -Name $ValueName).$ValueName
        $actual   = $verified[8]
        if ($actual -eq $bytes[8]) {
            Write-Host "Verification OK: byte[8] = $actual" -ForegroundColor Green
        } else {
            Write-Warning "Verification FAILED: byte[8] = $actual (expected $($bytes[8]))"
        }
    }
    catch {
        Write-Warning "Failed applying to ${Hive}: $_"
    }
}

# Main setup
$subKey          = "Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
$valueName       = "Settings"
$enableAutoHide  = -not $Revert

# Elevate if needed
if ($AllUsers -and -not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan

    $scriptArgs = @()
    if ($Revert)          { $scriptArgs += "-Revert" }
    if ($RestartExplorer) { $scriptArgs += "-RestartExplorer" }
    $scriptArgs += "-AllUsers"

    $elevArgs = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $MyInvocation.MyCommand.Path
    ) + $scriptArgs

    Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $elevArgs
    exit
}

# Apply to current or all users
if ($AllUsers) {
    $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
                Where-Object { (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*" }

    foreach ($p in $profiles) {
        $sid  = $p.PSChildName
        $hive = "HKEY_USERS\$sid"
        if (Test-Path "Registry::$hive\$subKey") {
            Set-BinaryRegistryValue -Hive $hive -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
        } else {
            Write-Warning "Hive not loaded for SID ${sid} - skipping"
        }
    }
} else {
    Set-BinaryRegistryValue -Hive "HKCU:" -SubKey $subKey -ValueName $valueName -EnableAutoHide:$enableAutoHide
}

# Restart Explorer or notify
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log off/in for changes to take effect." -ForegroundColor Cyan
}
