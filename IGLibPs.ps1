#!/usr/bin/env pwsh

# NOTE: This script is under initial development, do not use it in 
# production.

# Executes all the PowerShell utility scripts in this repository, in order to import all the definitions
# https://github.com/ajgorhoe/IGLib.modules.IGLibScriptsPS.git


# Execute definitions from PowerShell files in the repository root:
. "$(Join-Path "$PSScriptRoot" "ImportAllRoot.ps1")"


# Execute definitions from PowerShell files in the current directory:
. "$(Join-Path "$PSScriptRoot" "psutils/ImportAllUtils.ps1")"

