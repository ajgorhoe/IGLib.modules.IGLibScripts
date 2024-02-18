#!/usr/bin/env pwsh

# Executes all utility scripts in the current directory, in order to import all the definitions
# https://github.com/ajgorhoe/IGLib.modules.IGLibScriptsPS.git

# Execute definitions from other files:
. "$(Join-Path "$PSScriptRoot" "Common.ps1")"

# Check whether the current script has already been executed before:
CheckScriptExecuted $ExecutedScriptPath_ImportAll $MyInvocation.MyCommand.Path;
# Store scritp path in a variable in order to enable later verifications:
$ExecutedScriptPath_ImportAll = $MyInvocation.MyCommand.Path

# Execute all utility scripts:

# Execute basic utility scripts:
. $(Join-Path "$PSScriptRoot" "Common.ps1")
. $(Join-Path "$PSScriptRoot" "PSInfo.ps1")
. $(Join-Path "$PSScriptRoot" "File.ps1")
. $(Join-Path "$PSScriptRoot" "GitHelpers.ps1")

# Execute specialized scripts in psutils: 
. $(Join-Path "$PSScriptRoot" "psutils/UtilsWeb.ps1")

