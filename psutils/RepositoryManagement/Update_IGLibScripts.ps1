<#
    .SYNOPSIS
    Updates or clones a specific repository by calling UpdateOrCloneRepository.ps1 
    with parameters set through global variables.

    .DESCRIPTION
    This script defines a set of variables named with the 'Repository' prefix in 
    the same order as UpdateOrCloneRepository.ps1 parameters. Then, it invokes 
    UpdateOrCloneRepository.ps1 *without* passing parameters, relying on 
    -DefaultFromVars to pick up the values from these global variables.

    .NOTES
    Make sure UpdateOrCloneRepository.ps1 is accessible at the path specified in 
    $UpdatingScriptPath (absolute or relative).
#>

Write-Host "`n`n=======================================================\n"
Write-Host "Updating/cloning a specific repository...\n"

########################################################################
# Custom section (USER DEFINED):

# Path to UpdateOrCloneRepository.ps1
$UpdatingScriptPath = ".\\UpdateOrCloneRepository.ps1"

# Define parameter variables for UpdateOrCloneRepository.ps1
#    in the same order as that script's parameters:

$global:RepositoryDirectory = "IGLibScripts"
$global:RepositoryRef = "main"
$global:RepositoryAddress = "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"
$global:RepositoryRemote = "origin"
$global:RepositoryAddressSecondary = $null
$global:RepositoryRemoteSecondary = $null
$global:RepositoryAddressTertiary = "d:\backup_sync\bk_code\git\ig\misc\iglib_modules\IGLibScripts\"
$global:RepositoryRemoteTertiary = "local"
$global:RepositoryThrowOnErrors = $false

# End of custom section
########################################################################

# $global:RepositoryDefaultFromVars = $true # params set from variables above
$global:RepositoryBaseDirectory = $null   # base dir will be set to script dir 

# Set RepositoryBaseDirectory to the directory containing this script:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent
$scriptFilename = [System.IO.Path]::GetFileName($scriptPath)

# Set base directory for relative paths to the current script's directory:
$global:RepositoryBaseDirectory = $scriptDir

# If $UpdatingScriptPath is a relative path, convert it to absolute
if (-not [System.IO.Path]::IsPathRooted($UpdatingScriptPath)) {
    $UpdatingScriptPath = Join-Path $scriptDir $UpdatingScriptPath
}

Write-Host "`n${scriptFilename}:"
Write-Host "  RepositoryDirectory: $RepositoryDirectory"
Write-Host "  RepositoryAddress: $RepositoryAddress"
Write-Host "  RepositoryRef: $RepositoryRef"
# Write-Host "  UpdatingScriptPath: $UpdatingScriptPath"
# Write-Host "  RepositoryBaseDirectory: $RepositoryBaseDirectory `n"

./PrintRepositoryVariales.ps1

# Invoke UpdateOrCloneRepository.ps1 with no parameters, 
#    so it uses the global variables defined above:
Write-Host "`nCalling update script without parameters; it will use global variables..."
& $UpdatingScriptPath -Execute -DefaultFromVars

Write-Host "`nUpdating or cloning the repository completed.`n"
Write-Host "---------------------------------------------------------`n`n"
