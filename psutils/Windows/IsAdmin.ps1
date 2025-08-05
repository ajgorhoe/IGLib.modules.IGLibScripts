#!/usr/bin/env pwsh

# This script just writes to the standard output whetherr it is running in
# the administrator mode or not.

# Check if script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {

    Write-Warning "`nThis script is not running with Administrator privileges."
    Write-Warning "Some actions may fail, especially if applied to other users or system-wide.`n"
    # Optional: exit the script
    # exit 1
} else {
	Write-Host "`nThis script is running with Administrator privileges.'n" -ForegroundColor Green
}