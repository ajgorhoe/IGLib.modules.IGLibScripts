
# Clones or updates the depencencies repositories for IGLibSandbox.
Write-Host "`nCloning / updating dependency repositories of IGLibSandbox ..."

# Get the script directory such that relative paths can be resolved:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent
$scriptFilename = [System.IO.Path]::GetFileName($scriptPath)

Write-Host "Script directory: $scriptDir"

Write-Host "`nUpdating IGLibScripts:"
& $(Join-Path $scriptDir "UpdateRepo_IGLibScripts.ps1")

Write-Host "`nUpdating IGLibCore:"
& $(Join-Path $scriptDir "UpdateRepo_IGLibCore.ps1")

# # Write-Host "`nUpdating Westwind.Scripting:"
# & $(Join-Path $scriptDir "UpdateRepoExternal_Westwind.Scripting.ps1")

# # Write-Host "`nUpdating roslyn:"
# & $(join-path $scriptDir "UpdateRepoExternal_Roslyn.ps1")


Write-Host "  ... updating IGLibSandbox dependencies complete.`n"

