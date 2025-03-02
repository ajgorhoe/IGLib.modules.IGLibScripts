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

$RepositoryDirectory = "IGLibScripts"
$RepositoryRef = "main"
$RepositoryAddress = "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"
$RepositoryRemote = "origin"
$RepositoryAddressSecondary = $null
$RepositoryRemoteSecondary = $null
$RepositoryAddressTertiary = "d:\backup_sync\bk_code\git\ig\misc\iglib_modules\IGLibScripts\"
$RepositoryRemoteTertiary = "local"
$RepositoryThrowOnErrors = $false

# End of custom section
########################################################################

$RepositoryDefaultFromVars = $true # params set from variables above
$RepositoryBaseDirectory = $null   # base dir will be set to script dir 

# Set RepositoryBaseDirectory to the directory containing this script:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent
$scriptFilename = [System.IO.Path]::GetFileName($fullPath)
$RepositoryBaseDirectory = $scriptDir

# If $UpdatingScriptPath is a relative path, convert it to absolute
if (-not [System.IO.Path]::IsPathRooted($UpdatingScriptPath)) {
    $UpdatingScriptPath = Join-Path $scriptDir $UpdatingScriptPath
}

Write-Host "`n($scriptFilename):"
Write-Host "  RepositoryDirectory: $RepositoryDirectory"
Write-Host "  RepositoryAddress: $RepositoryAddress"
Write-Host "  RepositoryRef: $RepositoryRef"
# Write-Host "  UpdatingScriptPath: $UpdatingScriptPath"
# Write-Host "  RepositoryBaseDirectory: $RepositoryBaseDirectory `n"

# Invoke UpdateOrCloneRepository.ps1 with no parameters, 
#    so it uses the global variables defined above:
Write-Host "`nCalling update script without parameters; it will use global variables..."
& $UpdatingScriptPath -Execute -DefaultFromVars

Write-Host "`nUpdating or cloning the repository completed.`n"
Write-Host "`n---------------------------------------------------------`n`n"
