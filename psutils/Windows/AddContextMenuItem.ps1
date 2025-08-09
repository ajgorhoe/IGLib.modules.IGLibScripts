<#
.SYNOPSIS
    Adds or removes a custom Explorer context menu item for files, folders, and/or folder background.

.DESCRIPTION
    Creates registry entries under:
      Per-user: HKCU\Software\Classes\...\shell\<KeyName>
      All-users: HKLM\Software\Classes\...\shell\<KeyName>  (requires elevation)

    Targets:
      Files       -> *\shell\<KeyName>\command (argument default: "%1")
      Directories -> Directory\shell\<KeyName>\command (argument default: "%1")
      Background  -> Directory\Background\shell\<KeyName>\command (argument default: "%V")

.PARAMETER Title
    Display text (e.g., "Open with VS Code").

.PARAMETER CommandPath
    Full path to the executable (e.g., "C:\...\Code.exe").

.PARAMETER Arguments
    Optional arguments template for Files/Directories (default "%1"). Example: "-n -g `"%1`""

.PARAMETER BackgroundArguments
    Optional arguments template for folder background (default "%V").

.PARAMETER Icon
    Optional icon path (you can use the EXE; add ",0" for icon index if desired).

.PARAMETER KeyName
    Optional registry key name. If omitted, a safe key name is generated from Title.

.PARAMETER Targets
    One or more of: Files, Directories, Background. Default: Files, Directories.

.PARAMETER Revert
    Remove the item(s) instead of adding.

.PARAMETER AllUsers
    Apply under HKLM:\Software\Classes (requires elevation). Otherwise HKCU:\Software\Classes.

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
function Build-CommandLine {
    param([Parameter(Mandatory)][string]$ExePath,[Parameter(Mandatory)][string]$ArgTemplate)
    $exeQuoted = '"' + ($ExePath.Trim('"')) + '"'
    return ($exeQuoted + ' ' + $ArgTemplate)
}

# --- Elevation for HKLM ----------------------------------------------------
if ($AllUsers -and -not (Test-IsAdministrator)) {
    Write-Host "Elevation required. Relaunching as administrator..." -ForegroundColor Cyan
    $script = $MyInvocation.MyCommand.Path
    $passed = @()
    $passed += @('-Title', "`"$Title`"")
    $passed += @('-CommandPath', "`"$CommandPath`"")
    if ($Arguments -ne $null)           { $passed += @('-Arguments', "`"$Arguments`"") }
    if ($BackgroundArguments -ne $null) { $passed += @('-BackgroundArguments', "`"$BackgroundArguments`"") }
    if ($Icon)                          { $passed += @('-Icon', "`"$Icon`"") }
    if ($KeyName)                       { $passed += @('-KeyName', "`"$KeyName`"") }
    if ($Targets -and $Targets.Count)   { $passed += '-Targets'; $passed += $Targets }  # << pass each element
    if ($Revert)                        { $passed += '-Revert' }
    if ($RestartExplorer)               { $passed += '-RestartExplorer' }
    $passed += '-AllUsers'

    $cmd = "& `"$script`" $($passed -join ' '); Start-Sleep -Seconds 6"
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-Command',$cmd)
    exit
}

# --- Root via .NET Registry API (no wildcard issues) -----------------------
# (No Add-Type needed; Microsoft.Win32.Registry is already available.)
$root = if ($AllUsers) {
    [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\Classes', $true)
} else {
    [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $true)
}
if (-not $root) { throw "Unable to open registry root (Classes) for write." }

# Compute a safe key name if not provided
if (-not $KeyName) {
    $KeyName = [regex]::Replace($Title, '[^A-Za-z0-9_-]+', '_')
    if ([string]::IsNullOrWhiteSpace($KeyName)) { $KeyName = 'CustomMenuItem' }
}

# Map targets to literal subpaths (note the literal '*' key)
$map = @{
    Files       = "*\shell\$KeyName"
    Directories = "Directory\shell\$KeyName"
    Background  = "Directory\Background\shell\$KeyName"
}

foreach ($t in $Targets) {
    if (-not $map.ContainsKey($t)) { continue }
    $itemSubPath    = $map[$t]
    $commandSubPath = "$itemSubPath\command"

    if ($Revert) {
        try {
            if ($root.OpenSubKey($itemSubPath,$false)) {
                $root.DeleteSubKeyTree($itemSubPath, $false)
                Write-Host "Removed $t context item: $itemSubPath"
            } else {
                Write-Host "Nothing to remove for $t at: $itemSubPath"
            }
        } catch {
            Write-Warning "Failed to remove $t at ${itemSubPath}: $_"
        }
        continue
    }

    try {
        # Create keys
        $itemKey    = $root.CreateSubKey($itemSubPath, $true)
        $commandKey = $root.CreateSubKey($commandSubPath, $true)
        if (-not $itemKey -or -not $commandKey) { throw "CreateSubKey failed." }

        # Properties
        $itemKey.SetValue('MUIVerb', $Title, [Microsoft.Win32.RegistryValueKind]::String)
        if ($Icon) { $itemKey.SetValue('Icon', $Icon, [Microsoft.Win32.RegistryValueKind]::String) }

        $argTpl = if ($t -eq 'Background') { if ($BackgroundArguments) { $BackgroundArguments } else { '%V' } }
                  else { if ($Arguments) { $Arguments } else { '%1' } }

        $cmdLine = Build-CommandLine -ExePath $CommandPath -ArgTemplate $argTpl
        # Set unnamed default value:
        $commandKey.SetValue('', $cmdLine, [Microsoft.Win32.RegistryValueKind]::String)

        $itemKey.Close(); $commandKey.Close()
        Write-Host "Added/Updated $t context item: $itemSubPath"
        Write-Host "  Command = $cmdLine"
        if ($Icon) { Write-Host "  Icon    = $Icon" }
    } catch {
        Write-Warning "Failed to create/update $t at ${itemSubPath}: $_"
    }
}

$root.Close()

if ($RestartExplorer) {
    Restart-Explorer
} else {
    Write-Host "You may need to restart Explorer or log off/in for changes to take effect." -ForegroundColor Cyan
}
