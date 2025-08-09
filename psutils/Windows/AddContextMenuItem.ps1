<#
.SYNOPSIS
    Adds or removes a custom Explorer context menu item for files, folders, and/or folder background.

.DESCRIPTION
    Creates registry entries under:
      Per-user: HKCU:\Software\Classes\...\shell\<KeyName>
      All-users: HKLM:\Software\Classes\...\shell\<KeyName>  (requires elevation)

    Targets:
      - Files       -> *\shell\<KeyName>\command (argument default: "%1")
      - Directories -> Directory\shell\<KeyName>\command (argument default: "%1")
      - Background  -> Directory\Background\shell\<KeyName>\command (argument default: "%V")

.PARAMETER Title
    Display text in the context menu (e.g., "Open with VS Code").

.PARAMETER CommandPath
    Full path to the executable (e.g., "C:\Users\Me\AppData\Local\Programs\Microsoft VS Code\Code.exe").

.PARAMETER Arguments
    Optional arguments template for Files/Directories (default "%1"). Example: "-n -g `"%1`""

.PARAMETER BackgroundArguments
    Optional arguments template for folder background (default "%V").

.PARAMETER Icon
    Optional icon path (e.g., same as CommandPath). You may add ",0" to pick an icon index.

.PARAMETER KeyName
    Optional registry key name to use. If omitted, a safe key name is generated from Title.

.PARAMETER Targets
    One or more of: Files, Directories, Background. Default: Files, Directories.

.PARAMETER Revert
    Remove the registry keys for the specified Targets (instead of adding).

.PARAMETER AllUsers
    Apply under HKLM:\Software\Classes (requires elevation). Without it, use HKCU:\Software\Classes.

.PARAMETER RestartExplorer
    Restart Explorer after changes.

.EXAMPLE
    .\AddContextMenuItem.ps1 -Title "Open with VS Code" `
        -CommandPath "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
        -Icon "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
        -Targets Files,Directories -RestartExplorer
#>

param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$CommandPath,
    [string]$Arguments = '%1',
    [string]$BackgroundArguments = '%V',
    [string]$Icon,
    [string]$KeyName,
    [ValidateSet('Files','Directories','Background')][string[]]$Targets = @('Files','Directories'),
    [switch]$Revert,
    [switch]$AllUsers,
    [switch]$RestartExplorer
)

# --- Helpers ---------------------------------------------------------------

function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Explorer {
    Write-Host "Restarting Windows Explorer..."
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Process explorer.exe
}

# Normalize and quote the command properly
function Build-CommandLine {
    param(
        [Parameter(Mandatory)][string]$ExePath,
        [Parameter(Mandatory)][string]$ArgTemplate
    )
    # Ensure exe path is quoted once
    $exeQuoted = '"' + ($ExePath.Trim('"')) + '"'
    return ($exeQuoted + ' ' + $ArgTemplate)
}

# --- Elevation for HKLM ----------------------------------------------------

if ($AllUsers -and -not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan
    $script = $MyInvocation.MyCommand.Path
    # Rebuild the argument list for elevation
    $passed = @()
    $passed += @('-Title', "`"$Title`"")
    $passed += @('-CommandPath', "`"$CommandPath`"")
    if ($Arguments -ne $null)           { $passed += @('-Arguments', "`"$Arguments`"") }
    if ($BackgroundArguments -ne $null) { $passed += @('-BackgroundArguments', "`"$BackgroundArguments`"") }
    if ($Icon)                          { $passed += @('-Icon', "`"$Icon`"") }
    if ($KeyName)                       { $passed += @('-KeyName', "`"$KeyName`"") }
    if ($Targets)                       { $passed += @('-Targets', ($Targets -join ',')) }
    if ($Revert)                        { $passed += '-Revert' }
    if ($RestartExplorer)               { $passed += '-RestartExplorer' }
    $passed += '-AllUsers'

    $cmd = "& `"$script`" $($passed -join ' '); Start-Sleep -Seconds 6"
    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile','-ExecutionPolicy','Bypass','-Command', $cmd
    )
    exit
}

# --- Target map ------------------------------------------------------------

$baseRoot = if ($AllUsers) { 'HKLM:\Software\Classes' } else { 'HKCU:\Software\Classes' }

$targetMap = @{
    Files       = @{ ShellPath = Join-Path $baseRoot '*\shell';                         ArgDefault = '%1' }
    Directories = @{ ShellPath = Join-Path $baseRoot 'Directory\shell';                 ArgDefault = '%1' }
    Background  = @{ ShellPath = Join-Path $baseRoot 'Directory\Background\shell';      ArgDefault = '%V' }
}

# Compute a safe key name if not provided
if (-not $KeyName) {
    $KeyName = [regex]::Replace($Title, '[^A-Za-z0-9_-]+', '_')
    if ([string]::IsNullOrWhiteSpace($KeyName)) { $KeyName = 'CustomMenuItem' }
}

# --- Core apply/remove -----------------------------------------------------

foreach ($t in $Targets) {
    if (-not $targetMap.ContainsKey($t)) { continue }
    $shellPath = $targetMap[$t].ShellPath
    $argTpl    = $targetMap[$t].ArgDefault

    # Allow override for Files/Directories (Arguments) and Background (BackgroundArguments)
    $argToUse = if ($t -eq 'Background') { $BackgroundArguments } else { $Arguments }
    if (-not $argToUse) { $argToUse = $argTpl }

    $itemKey      = Join-Path $shellPath $KeyName
    $commandKey   = Join-Path $itemKey  'command'

    if ($Revert) {
        if (Test-Path $itemKey) {
            try {
                Remove-Item -Path $itemKey -Recurse -Force
                Write-Host "Removed $t context item at: $itemKey"
            } catch {
                Write-Warning "Failed to remove $t key at ${itemKey}: $_"
            }
        } else {
            Write-Host "Nothing to remove for $t at: $itemKey"
        }
        continue
    }

    # Create/Update
    try {
        if (-not (Test-Path $itemKey))     { New-Item -Path $itemKey     -Force | Out-Null }
        if (-not (Test-Path $commandKey))  { New-Item -Path $commandKey  -Force | Out-Null }

        # Visible label
        New-ItemProperty -Path $itemKey -Name 'MUIVerb' -Value $Title -Force | Out-Null

        # Optional icon
        if ($Icon) {
            New-ItemProperty -Path $itemKey -Name 'Icon' -Value $Icon -Force | Out-Null
        }

        # Command line
        $cmdLine = Build-CommandLine -ExePath $CommandPath -ArgTemplate $argToUse
        New-ItemProperty -Path $commandKey -Name '(Default)' -Value $cmdLine -Force | Out-Null

        Write-Host "Added/Updated $t context item at: $itemKey"
        Write-Host "  Command = $cmdLine"
        if ($Icon) { Write-Host "  Icon    = $Icon" }

    } catch {
        Write-Warning "Failed to create/update $t key at ${itemKey}: $_"
    }
}

if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log off/in for changes to take effect." -ForegroundColor Cyan
}
