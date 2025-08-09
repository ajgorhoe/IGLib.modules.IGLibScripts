<#
.SYNOPSIS
    Demo wrapper that adds/removes "Open with VS Code" to Explorer context menu for files and folders.

.DESCRIPTION
    Calls AddContextMenuItem.ps1 with sane defaults for Visual Studio Code.
    Detects VS Code path from typical locations:
      - %LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe
      - %ProgramFiles%\Microsoft VS Code\Code.exe
      - %ProgramFiles(x86)%\Microsoft VS Code\Code.exe
      - Or falls back to `code.exe` from PATH

.PARAMETER Revert
    Remove the menu entry instead of adding it.

.PARAMETER AllUsers
    Apply for all users (requires elevation).

.PARAMETER RestartExplorer
    Restart Explorer after the change.
#>

param(
    [switch]$Revert,
    [switch]$AllUsers,
    [switch]$RestartExplorer
)

# Locate AddContextMenuItem.ps1 (assumed next to this script)
$helper = Join-Path $PSScriptRoot 'AddContextMenuItem.ps1'
if (-not (Test-Path $helper)) {
    Write-Error "AddContextMenuItem.ps1 not found at: $helper"
    exit 1
}

# Candidate VS Code locations
$pathsToCheck = @(
    (Join-Path $env:LOCALAPPDATA            'Programs\Microsoft VS Code\Code.exe'),
    (Join-Path ${env:ProgramFiles}          'Microsoft VS Code\Code.exe'),
    (Join-Path ${env:ProgramFiles(x86)}     'Microsoft VS Code\Code.exe')
) | Where-Object { $_ -and (Test-Path $_) }

# Fallback: code from PATH
if (-not $pathsToCheck -or $pathsToCheck.Count -eq 0) {
    $gc = Get-Command code -ErrorAction SilentlyContinue
    if ($gc) { $pathsToCheck = @($gc.Source) }
}

if (-not $pathsToCheck -or $pathsToCheck.Count -eq 0) {
    Write-Error "Unable to locate VS Code (Code.exe). Please install VS Code or adjust the script."
    exit 1
}

$codePath  = $pathsToCheck | Select-Object -First 1
$menuTitle = 'Open with VS Code'
$iconPath  = $codePath

# For Files/Directories, pass "%1" quoted to handle spaces
$argsTemplate = '`"%1`"'

# Build argument list for the helper script
$base = @(
    '-Title',        $menuTitle,
    '-CommandPath',  $codePath,
    '-Arguments',    $argsTemplate,
    '-Icon',         $iconPath,
    '-Targets',      'Files,Directories'
)

if ($Revert)          { $base += '-Revert' }
if ($AllUsers)        { $base += '-AllUsers' }
if ($RestartExplorer) { $base += '-RestartExplorer' }

# Call helper in this PowerShell process
& $helper @base
