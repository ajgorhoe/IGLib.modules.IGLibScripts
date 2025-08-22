<#
.SYNOPSIS
  Add or remove a custom Explorer context menu item for Files / Directories / Background.

.DESCRIPTION
  Creates (or removes with -Revert) the registry keys for a classic shell verb under:
    • Current user: HKCU:\Software\Classes\...
    • All users   : HKLM:\Software\Classes\...  (requires elevation)

  Targets:
    - Files       → *\shell\<KeyName>\command      (argument default: "%1")
    - Directories → Directory\shell\<KeyName>\command
    - Background  → Directory\Background\shell\<KeyName>\command (argument default: "%V")

  The item key's default value and "MUIVerb" are both set to the Title for compatibility.
  The command's default value is the quoted CommandPath plus the chosen argument placeholder.

.PARAMETER Title
  Menu caption to show (e.g., "Open with VS Code").

.PARAMETER CommandPath
  Full path to the executable (e.g., C:\Path\To\Code.exe).

.PARAMETER Arguments
  Argument template for Files/Directories (default: "%1").

.PARAMETER BackgroundArguments
  Argument template for Background (default: "%V").

.PARAMETER Icon
  Optional icon path to display (e.g., the same executable).

.PARAMETER Targets
  One or more of: Files, Directories, Background. Default: Files,Directories.

.PARAMETER KeyName
  Optional registry key name under \shell\. If omitted, derived from Title
  by replacing non-alphanumerics with underscores.

.PARAMETER Revert
  Remove the item for the selected targets instead of creating it.

.PARAMETER AllUsers
  Write under HKLM:\Software\Classes for all users (requires elevation).
  Prints a concise summary at the end.

.PARAMETER RestartExplorer
  Restart Explorer after changes (affects current session only).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Title,
    [Parameter(Mandatory)][string]$CommandPath,
    [string]$Arguments,
    [string]$BackgroundArguments,
    [string]$Icon,
    [ValidateSet('Files','Directories','Background')]
    [string[]]$Targets = @('Files','Directories'),
    [string]$KeyName,
    [switch]$Revert,
    [switch]$AllUsers,
    [switch]$RestartExplorer
)

# ---------------- Utilities ----------------

function Test-IsAdmin {
    try {
        $id  = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr  = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
    } catch { return $false }
}

function Restart-Explorer {
    Write-Host "Restarting Windows Explorer..."
    try {
        Get-Process explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Process explorer.exe
    } catch {
        Write-Warning "Failed to restart Explorer: $($_.Exception.Message)"
    }
}

function Get-RootHive {
    param([switch]$Machine)
    if ($Machine) { return 'HKLM:\Software\Classes' } else { return 'HKCU:\Software\Classes' }
}

function Get-ItemSubPath {
    param([ValidateSet('Files','Directories','Background')] [string]$Target, [string]$KeyName)
    switch ($Target) {
        'Files'       { return "*\shell\$KeyName" }
        'Directories' { return "Directory\shell\$KeyName" }
        'Background'  { return "Directory\Background\shell\$KeyName" }
    }
}

function Build-CommandLine {
    param([string]$ExePath, [string]$ArgTemplate)
    # Always quote the exe; args may already contain quotes around %1 / %V.
    $quotedExe = '"' + $ExePath + '"'
    if ([string]::IsNullOrWhiteSpace($ArgTemplate)) { return $quotedExe }
    return "$quotedExe $ArgTemplate"
}

function Get-SafeKeyNameFromTitle {
    param([string]$Title)
    $k = ($Title -replace '[^A-Za-z0-9]+','_').Trim('_')
    if ([string]::IsNullOrWhiteSpace($k)) { $k = 'Custom_Command' }
    return $k
}

# --- Summary helpers for AddContextMenuItem (HKLM path) --------------------
function New-HKLMReport {
    [ordered]@{
        RootHive      = 'HKLM:\Software\Classes'
        Succeeded     = @()
        Failed        = @()
        FailedDetails = @()
    }
}
function Write-HKLMReport {
    param([hashtable]$Report)
    Write-Host ""
    Write-Host "=== All-Users summary (HKLM\Software\Classes) ===" -ForegroundColor Cyan
    Write-Host ("Targets succeeded : {0}" -f ($(if ($Report.Succeeded.Count) { $Report.Succeeded -join ', ' } else { 'None' })))
    if ($Report.Failed.Count) {
        Write-Host ("Targets failed    : {0}" -f ($Report.Failed -join ', '))
    }
}

# ------------- Elevation for -AllUsers -------------

if ($AllUsers -and -not (Test-IsAdmin)) {
    Write-Host "Elevation required. Relaunching as administrator..."
    # Re-launch self with same params, plus a brief sleep so the window stays visible
    $script = '"' + $PSCommandPath + '"'
    $args   = @()
    $args += ('-Title ' + ('"'+$Title+'"'))
    $args += ('-CommandPath ' + ('"'+$CommandPath+'"'))
    if ($Arguments)           { $args += ('-Arguments ' + ('"'+$Arguments+'"')) }
    if ($BackgroundArguments) { $args += ('-BackgroundArguments ' + ('"'+$BackgroundArguments+'"')) }
    if ($Icon)                { $args += ('-Icon ' + ('"'+$Icon+'"')) }
    if ($KeyName)             { $args += ('-KeyName ' + ('"'+$KeyName+'"')) }
    if ($Targets)             { $args += ($Targets | ForEach-Object { '-Targets ' + $_ }) }  # pass each target explicitly
    if ($Revert)              { $args += '-Revert' }
    if ($AllUsers)            { $args += '-AllUsers' }
    if ($RestartExplorer)     { $args += '-RestartExplorer' }
    $joined = $args -join ' '
    $full   = "& $script $joined; Start-Sleep -Seconds 6"
    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $full"
    exit
}

# ---------------- Main logic ----------------

$root = Get-RootHive -Machine:$AllUsers

if (-not $KeyName) { $KeyName = Get-SafeKeyNameFromTitle -Title $Title }

# Per-target defaults
if (-not $Arguments)           { $Arguments = '"%1"' }
if (-not $BackgroundArguments) { $BackgroundArguments = '"%V"' }

# Initialize HKLM summary if needed
$Report = $null
if ($AllUsers) { $Report = New-HKLMReport }

foreach ($t in $Targets) {
    $itemSubPath    = Get-ItemSubPath -Target $t -KeyName $KeyName
    $itemKeyPath    = Join-Path $root $itemSubPath
    $commandSubPath = Join-Path $itemSubPath 'command'
    $commandKeyPath = Join-Path $root $commandSubPath

    if ($Revert) {
        try {
            if (Test-Path -LiteralPath $itemKeyPath) {
                Remove-Item -LiteralPath $itemKeyPath -Recurse -Force
                Write-Host "Removed $t context item at: ${itemSubPath}"
                if ($Report) { $Report.Succeeded += $t }
            } else {
                Write-Host "Nothing to remove for $t at: ${itemSubPath}"
                if ($Report) { $Report.Succeeded += $t }
            }
        } catch {
            Write-Warning "Failed to remove $t at ${itemSubPath}: $($_.Exception.Message)"
            if ($Report) {
                $Report.Failed        += $t
                $Report.FailedDetails += "${t}: $($_.Exception.Message)"
            }
        }
        continue
    }

    # Create/Update
    try {
        # Ensure keys exist
        $null = New-Item -LiteralPath $itemKeyPath -Force -ErrorAction Stop
        $null = New-Item -LiteralPath $commandKeyPath -Force -ErrorAction Stop

        # Menu text: default value and MUIVerb
        # Set default value (unnamed)
        Set-ItemProperty -LiteralPath $itemKeyPath -Name '(default)' -Value $Title -ErrorAction SilentlyContinue
        # Also set MUIVerb explicitly
        New-ItemProperty -LiteralPath $itemKeyPath -Name 'MUIVerb' -Value $Title -PropertyType String -Force | Out-Null

        # Optional icon
        if ($Icon) {
            New-ItemProperty -LiteralPath $itemKeyPath -Name 'Icon' -Value $Icon -PropertyType String -Force | Out-Null
        }

        # Build command line
        $argTpl = if ($t -eq 'Background') { $BackgroundArguments } else { $Arguments }
        $cmd    = Build-CommandLine -ExePath $CommandPath -ArgTemplate $argTpl

        # Set command
        New-ItemProperty -LiteralPath $commandKeyPath -Name '(default)' -Value $cmd -PropertyType String -Force | Out-Null

        Write-Host "Added/Updated $t context item: ${itemSubPath}"
        Write-Host "  Command = $cmd"
        if ($Icon) { Write-Host "  Icon    = $Icon" }

        if ($Report) { $Report.Succeeded += $t }
    } catch {
        Write-Warning "Failed to create/update $t at ${itemSubPath}: $($_.Exception.Message)"
        if ($Report) {
            $Report.Failed        += $t
            $Report.FailedDetails += "${t}: $($_.Exception.Message)"
        }
    }
}

if ($AllUsers -and $Report) { Write-HKLMReport -Report $Report }

if ($RestartExplorer) { Restart-Explorer }
