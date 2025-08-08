<#
.SYNOPSIS
    Attempts to hide the Windows taskbar by patching the StuckRects3 binary registry key.

.DESCRIPTION
    Modifies byte 8 of the "Settings" value in:
      HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3
    to set/clear the auto-hide flag, then verifies.
    Supports:
      -Revert         : clears the auto-hide bit
      -AllUsers       : loads each user hive (requires elevation)
      -RestartExplorer: restarts explorer.exe
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
    Stop-Process explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

function Set-BinaryRegistryValue {
    param (
        [string]$Hive,           # e.g. "HKCU:" or "HKEY_USERS\<sid>"
        [string]$SubKey,         # e.g. "Software\...\StuckRects3"
        [string]$ValueName,      # "Settings"
        [bool]  $EnableAutoHide  # $true sets bit, $false clears
    )

    $psPath = if ($Hive -match ':$') { "$Hive\$SubKey" }
              else { "Registry::$Hive\$SubKey" }

    if (-not (Test-Path $psPath)) {
        Write-Warning "Registry path not found: $psPath"
        return
    }

    try {
        # Open the hive
        $root = switch -regex ($Hive) {
            "^HKCU:$"    { [Microsoft.Win32.Registry]::CurrentUser }
            "^HKLM:$"    { [Microsoft.Win32.Registry]::LocalMachine }
            "^HKEY_USERS\\(.+)$" {
                $sid = $Matches[1]
                [Microsoft.Win32.RegistryKey]::OpenBaseKey(
                    [Microsoft.Win32.RegistryHive]::Users,
                    [Microsoft.Win32.RegistryView]::Default
                ).OpenSubKey($sid, $true)
            }
        }
        $key = $root.OpenSubKey($SubKey, $true)
        if (-not $key) {
            Write-Warning "Cannot open $SubKey under $Hive"
            return
        }

        $bytes = $key.GetValue($ValueName)
        if (-not $bytes -or $bytes.Length -lt 9) {
            Write-Warning "Invalid data in $psPath"
            $key.Close(); return
        }

        if ($EnableAutoHide) {
            $bytes[8] = $bytes[8] -bor 0x08
            Write-Host "Enabled auto-hide bit: byte[8]=$($bytes[8])"
        } else {
            $bytes[8] = $bytes[8] -band 0xF7
            Write-Host "Disabled auto-hide bit: byte[8]=$($bytes[8])"
        }

        $key.SetValue($ValueName, $bytes, [Microsoft.Win32.RegistryValueKind]::Binary)
        $key.Close()
        Write-Host "Updated $psPath\$ValueName"

        # verify
        $actual = (Get-ItemProperty -Path $psPath -Name $ValueName).$ValueName[8]
        if ($actual -eq $bytes[8]) {
            Write-Host "Verification OK: byte[8]=$actual" -ForegroundColor Green
        } else {
            Write-Warning "Verification FAILED: byte[8]=$actual (expected $($bytes[8]))"
        }
    }
    catch {
        Write-Warning "Error writing to ${Hive}: $_"
    }
}

# Configuration
$subKey         = "Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
$valueName      = "Settings"
$enableAutoHide = -not $Revert

# Elevate if needed
if ($AllUsers -and -not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan
    $script = $MyInvocation.MyCommand.Path
    $args   = @()
    if ($Revert)          { $args += "-Revert" }
    if ($RestartExplorer) { $args += "-RestartExplorer" }
    $args += "-AllUsers"

    $cmd = "& `"$script`" $($args -join ' '); Start-Sleep -Seconds 6"
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        "-NoProfile", "-ExecutionPolicy","Bypass","-Command", $cmd
    )
    exit
}

# AllUsers branch now loads each hive and unloads it
if ($AllUsers) {
    $profiles = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList" |
        Where-Object { (Get-ItemProperty $_.PSPath).ProfileImagePath -notlike "*systemprofile*" }

    foreach ($p in $profiles) {
        $sid         = $p.PSChildName
        $profilePath = (Get-ItemProperty -Path $p.PSPath).ProfileImagePath
        $ntUserDat   = Join-Path $profilePath 'NTUSER.DAT'
        $tempHive    = "Temp_$sid"

        if (-not (Test-Path $ntUserDat)) {
            Write-Warning "NTUSER.DAT not found for SID $sid; skipping"
            continue
        }

        Write-Host "Loading hive for SID $sid..."
        & reg.exe load "HKU\$tempHive" $ntUserDat

        try {
            Set-BinaryRegistryValue -Hive "HKEY_USERS\$tempHive" -SubKey $subKey `
                -ValueName $valueName -EnableAutoHide:$enableAutoHide
        } finally {
            Write-Host "Unloading hive for SID $sid..."
            & reg.exe unload "HKU\$tempHive"
        }
    }
}
else {
    # Single user
    Set-BinaryRegistryValue -Hive "HKCU:" -SubKey $subKey `
        -ValueName $valueName -EnableAutoHide:$enableAutoHide
}

# Restart or prompt
if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log off/in for changes to take effect." -ForegroundColor Cyan
}
