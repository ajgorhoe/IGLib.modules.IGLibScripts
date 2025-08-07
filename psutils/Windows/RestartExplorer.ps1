#!/usr/bin/env pwsh

# This script restarts the Windows' Explorer process. This is sometimes
# necessary after settings that govern Explorer behavior have been changed, 
# e.g. by modifying registry keys.

# Function to restart Explorer:
function Restart-Explorer {
    Write-Host "`nRestarting Windows Explorer..." -ForegroundColor Cyan
    Stop-Process -Name explorer -Force
	Start-Sleep -Milliseconds 600
    Start-Process Explorer
    Write-Host "  ... Windows Explorer restarted.`n" -ForegroundColor Green
}

Restart-Explorer
