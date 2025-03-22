
# Clones or updates all repositories contained in this directory.
Write-Host "`n`nCloning / updating all repositories in directory XXYY/ ...`n"

# Get the script directory such that relative paths can be resolved:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent
# $scriptFilename = [System.IO.Path]::GetFileName($scriptPath)

Write-Host "Script directory: $s+criptDir"

# Write-Host "`nUpdating basic directories:"
# & $(Join-Path $scriptDir "UpdateRepoGroup_DirectoryBasic.ps1")

Write-Host "`nUpdating '':"
& $(Join-Path $scriptDir "UpdateRepo_.ps1")

Write-Host "  ... updating repositories in XXYY/ completed.`n`n"

