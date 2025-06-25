
# Git-Cleans all repository clones in this directory.
Write-Host "`n`nGit-cleaning all repository clones in directory XXYY/ ...`n"

# Get the script directory such that relative paths can be resolved:
$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath -Parent
# $scriptFilename = [System.IO.Path]::GetFileName($scriptPath)

Write-Host "Script directory: $scriptDir"

function Write-Warn {
    param([string]$Message)
    Write-Host "Warning: $Message" -ForegroundColor Yellow
}

function CleanRepository {
    param([string]$Directory)
	$currentDirSaved = $(Get-Location)
	try {
		if (-Not (Test-Path -Path $Directory)) {
			Write-Warn "CleanRepository: Directory doesn't exist:`n    $Directory"
			return
		}
		# Write-Host "`nExecuting CleanRepository $Directory ..."
		# Write-Host "Current dir: $currentDirSaved"
		Set-Location -Path "$Directory"
		# Write-Host "Current dir after change: $(Get-Location)"
		# Write-Host cleaning git repo...
		git clean -f -x -d
	}
	catch {
		Write-Warn "  WARNING: Error occurred when executing CleanRepository."
	}
	finally {
		Set-Location -Path "$currentDirSaved"
		# Write-Host "Current dir after changing back: $(Get-Location)"
		# Write-Host "CleanRepository completed.`n"
	}
}


# Write-Host "`nGit-cleaning repository basic directories:"
# & $(Join-Path $scriptDir "CleanRepoGroup_DirectoryBasic.ps1")

Write-Host "`nGit-cleaning repository '' ..."
try {
	& CleanRepository $(Join-Path $scriptDir "")
}
catch {
	Write-Warn "    Directory does not exist, or error occurred."
}
Write-Host "  ... cleaning directory completed."


Write-Host "`n... cleaning repositories in XXYY/ completed.`n`n"

