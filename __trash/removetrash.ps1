
# Removes contents of the trash_contents/ subdirectory.
# Also creates trash_contents/ and save/ subdirectories if they don't exist.

Write-Host "`n"
Write-Host "REMOVING contents of the trash_contents/ directory;"
Write-Host "  creating save/ and trash_contents/ subdirectories if they don't exist..."



# Get the script directory such that relative paths can be resolved:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent

Write-Host Base path:
Write-Host "  $scriptDir"

# Get absolute paths of save/ and trash_contents/ directories:
$saveDir =   $(Join-Path $scriptDir "save")
$removeDir = $(Join-Path $scriptDir "trash_contents")

# Write-Host Removed dir. path:
# Write-Host "  $removeDir"

# Remove the complete trash_contents/ sub-directort:
Write-Host Removing trash_contents/ ...
Remove-Item -Recurse -Force -Path $removeDir

Write-Host "  ... trash_contents/ removed."

# If the save/ and trash_contents/ subdirectories do not exist, create them:

New-Item -ItemType Directory -Force -Path $saveDir > $null
New-Item -ItemType Directory -Force -Path $removeDir > $null

Write-Host "  ... subdirectories created."
Write-Host "`n"

