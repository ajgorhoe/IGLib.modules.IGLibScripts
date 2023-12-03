#!/usr/bin/env pwsh

# Executes all the PowerShell utility scripts in the current directory, in order to import all the definitions


# Execute definitions from PowerShell files in the current directory:
. "$(Join-Path "$PSScriptRoot" "UtilSys.ps1")"

