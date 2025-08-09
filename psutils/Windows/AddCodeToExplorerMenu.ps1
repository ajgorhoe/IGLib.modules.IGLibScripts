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

function Write-HashTable {
    param(
        [hashtable]$Table
    )
    if ($null -eq $Table) {
        Write-Host "  NULL hashtable"
        return
    }
    if ($Table.Count -eq 0) {
        Write-Host "  EMPTY hashtable"
        return
    }
    foreach ($key in $Table.Keys) {
        Write-Host "  ${key}: $($Table[$key])"
    }
}

function Write-Array {
    param(
        [object[]]$Array
    )
    if ($null -eq $Array) {
        Write-Host "  NULL"
        return
    }
    if ($Array.Count -eq 0) {
        Write-Host "  EMPTY"
        return
    }
    for ($i = 0; $i -lt $Array.Count; $i++) {
        Write-Host "  ${i}: $($Array[$i])"
    }
}

# Define fixed parameters
$calledScriptName = "AddContextMenuItem.ps1"
$verificationScriptName = "AddCode_Verify.ps1"
$indent = "  "

# Inform user of the task to be performed, output script parameters:
Write-Host "`n`nAdding VS Code to Explorer's context menu ($($MyInvocation.MyCommand.Name))..." -ForegroundColor Green
Write-Host "`nScript parameters:"
Write-HashTable $PSBoundParameters
Write-Host "  Positional:"
Write-Array $args

# Locate AddContextMenuItem.ps1 (assumed next to this script)
$calledScriptPath = Join-Path $PSScriptRoot $calledScriptName
if (-not (Test-Path $calledScriptPath)) {
    Write-Error "$calledScriptName not found at: $calledScriptPath"
    exit 1
}

# Candidate VS Code locations
$pathsToCheck = @(
    (Join-Path $env:LOCALAPPDATA        'Programs\Microsoft VS Code\Code.exe'),
    (Join-Path ${env:ProgramFiles}      'Microsoft VS Code\Code.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft VS Code\Code.exe')
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

Write-Host "`nIdentified path to VS Code: `n  $codePath"

# For Files/Directories, pass "%1" quoted to handle spaces
$argsTemplate = '"%1"'

# Build parameter hashtable for the helper (splatting)
$params = @{
    Title       = $menuTitle
    CommandPath = $codePath
    Arguments   = $argsTemplate
    Icon        = $codePath
    Targets     = @('Files','Directories')  # IMPORTANT: array, not comma-separated string
}

if ($Revert)          { $params.Revert = $true }
if ($AllUsers)        { $params.AllUsers = $true }
if ($RestartExplorer) { $params.RestartExplorer = $true }

# Write-Host "`nThe following script will be run:`n  $calledScriptPath"
Write-Host "`nParameters to be passed to ${calledScriptName}:"
Write-HashTable $params

# Call the script in this PowerShell process:
Write-Host "`nCalling the main script, $calledScriptName ..." -ForegroundColor Green
& $calledScriptPath @params
Write-Host "  ... $calledScriptName completed." -ForegroundColor Green

# Call the verification scrip:
Write-Host "`nVerifying the registry entries (this may take a while!) ..." -ForegroundColor Green
$verificationScriptPath = Join-Path $PSScriptRoot $verificationScriptName
if (-not (Test-Path $verificationScriptPath)) {
    Write-Warning "$verificationScriptName not found at:$(${indent} + $verificationScriptPath) `n  ... verification skipped."
} else {
    & $verificationScriptPath
    Write-Host "  ... verification completed." -ForegroundColor Green
}

Write-Host "`n  ... adding VS Code to Explorer's context menu completed.`n" -ForegroundColor Green
