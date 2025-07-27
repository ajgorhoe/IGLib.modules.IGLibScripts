
# Removes contents of the trash_contents/ subdirectory.
# Also creates trash_contents/ and save/ subdirectories if they don't exist.

Write-Host
Write-Host "REMOVING contents of the trash_contents/ directory"
Write-Host "  and creating save/ and trash_contents/ subdirectories if they"
Write-Host "  don't exist..."



# Get the script directory such that relative paths can be resolved:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent

Write-Host Base path:
Write-Host "  $scriptDir"

# Get absolute paths of save/ and trash_contents/ directories:
$saveDir =   $(Join-Path $scriptDir "save")
$removeDir = $(Join-Path $scriptDir "trash_contents")

Write-Host Removed dir. path:
Write-Host $removeDir

# Remove the complete trash_contents/ sub-directort:
# Remove-Item -Recurse -Force -Path $removeDir

Write-Host "  ... contents of trash_contents/ removed."

# If the save/ and trash_contents/ subdirectories do not exist, create them:
# New-Item -ItemType Directory -Force -Path $saveDir
# New-Item -ItemType Directory -Force -Path $removeDir

Write-Host "  ... subdirectories created."
Write-Host

