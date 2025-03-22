
# Removes all repository clones in this directory.
Write-Host "`n`nRemoving all repository clones in directory XXYY/ ...`n"

# Get the script directory such that relative paths can be resolved:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent
# $scriptFilename = [System.IO.Path]::GetFileName($scriptPath)

Write-Host "Script directory: $scriptDir"

# Write-Host "`nRemoving basic directories:"
# & $(Join-Path $scriptDir "RemoveRepoGroup_DirectoryBasic.ps1")

Write-Host "`nRemoving '' ..."
try {
	& Remove-Item -Recurse -Force $(Join-Path $scriptDir "")
}
catch {
	Write-Host "    Directory does not exist, or error occurred."
}
Write-Host "  ... removing directory completed."


Write-Host "`n... removing repositories in XXYY/ completed.`n`n"

