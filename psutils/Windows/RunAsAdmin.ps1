#!/usr/bin/env pwsh

param (
    [int]$SleepSeconds = 0
)


# This script checks whether it runs in administrator mode or not. If not, it
# restarts itself in administrator mode. At the begining, it writes to the
# standard output whether it runs in admnistrator mode or not.

# Check if script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Warning "`nThis script is not running with Administrator privileges."
    Write-Warning "Some actions may fail, especially if applied to other users or system-wide.`n"
	
	Write-Host "`nThe script is being restarted in administrator mode.`n"
} else {
	Write-Host "`nThis script is running with Administrator privileges.'n" -ForegroundColor Green
}

# Id not in Administrator mode, prompt for elevation to Administrator mode and
# re-run itself:

# Check if running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Host "Restarting with administrator privileges..." -ForegroundColor Cyan

    # Build script command with sleep at the end
    $escapedScript = "`"$PSCommandPath`""
    $cmd = "-NoProfile -ExecutionPolicy Bypass -Command `"& { & $escapedScript; Start-Sleep -Seconds 3 }`""

    Start-Process powershell -ArgumentList $cmd -Verb RunAs
    exit
}
