<#
.SYNOPSIS
  Add or remove a custom Explorer context menu item for Files / Directories / Background.

.DESCRIPTION
  Creates (or removes with -Revert) the registry keys for a classic shell verb under:
    • Current user: HKCU\Software\Classes\...
    • All users   : HKLM\Software\Classes\...  (requires elevation)

  Targets:
    - Files       → *\shell\<KeyName>\command      (argument default: "%1")
    - Directories → Directory\shell\<KeyName}\command
    - Background  → Directory\Background\shell\<KeyName>\command (argument default: "%V")

  Uses the Microsoft.Win32.Registry .NET API to avoid wildcard issues with the registry provider.

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
  Optional registry key name under \shell\. If omitted, derived from Title.

.PARAMETER Revert
  Remove the item for the selected targets instead of creating it.

.PARAMETER AllUsers
  Write under HKLM\Software\Classes for all users (requires elevation).
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
function Get-ClassesRootKey {
    param([switch]$Machine)
    if ($Machine) {
        return [Microsoft.Win32.Registry]::LocalMachine.OpenSubKey('Software\Classes', $true)
    } else {
        return [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\Classes', $true)
    }
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
        RootHive      = 'HKLM\Software\Classes'
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

# Helper: single-quote and escape for -Command string
function SQ { param([string]$s) if ($null -eq $s) { "''" } else { "'" + ($s -replace "'", "''") + "'" } }


# ------------- Auxiliary functions for printing passed parameters: -------------

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

# ------------------- Start of main script logic -------------------

# Output of intro and parameters passed to the script:
Write-Host "`nAdding or removing Explorer menu item ($($MyInvocation.MyCommand.Name))..." -ForegroundColor Green
Write-Host "`nScript parameters:"
Write-HashTable $PSBoundParameters
Write-Host "  Positional:"
Write-Array $args
Write-Host "Targets parameter:"
Write-Array $Targets
Write-Host

# # Below debug code causes an error, commented for now:
# # DEBUG: show bound parameters once
# if ($PSBoundParameters.Count) {
#   Write-Host ("`n[DEBUG] Bound params: " + ($PSBoundParameters.Keys | Sort-Object | ForEach-Object {
#     "$_=$($PSBoundParameters[$_]-join ',')"
#   } | Join-String -Separator '  '))
# }

# ------------- Elevation for -AllUsers (robust quoting; Targets as array literal) -------------

if ($AllUsers -and -not (Test-IsAdmin)) {
    Write-Host "Elevation required. Relaunching as administrator..."

    $scriptSingleQuoted = SQ $PSCommandPath

    $args = @()
    $args += ('-Title ' + (SQ $Title))
    $args += ('-CommandPath ' + (SQ $CommandPath))
    if ($Arguments)           { $args += ('-Arguments ' + (SQ $Arguments)) }
    if ($BackgroundArguments) { $args += ('-BackgroundArguments ' + (SQ $BackgroundArguments)) }
    if ($Icon)                { $args += ('-Icon ' + (SQ $Icon)) }
    if ($KeyName)             { $args += ('-KeyName ' + (SQ $KeyName)) }
    if ($Targets)             { $args += ('-Targets ' + ($Targets -join ',')) }  # NOTE: unquoted, comma-separated
    if ($Revert)              { $args += '-Revert' }
    if ($AllUsers)            { $args += '-AllUsers' }
    if ($RestartExplorer)     { $args += '-RestartExplorer' }

    # Build final -Command string. Ensure the Targets token remains unquoted.
    $joined = ($args -join ' ')
    $full   = "& $scriptSingleQuoted $joined; Start-Sleep -Seconds 6"

    Start-Process powershell.exe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command $full"
    exit
}

# ---------------- Main logic (using Microsoft.Win32.Registry) ----------------

if (-not $KeyName) { $KeyName = Get-SafeKeyNameFromTitle -Title $Title }
if (-not $Arguments)           { $Arguments = '"%1"' }
if (-not $BackgroundArguments) { $BackgroundArguments = '"%V"' }

$rootKey = Get-ClassesRootKey -Machine:$AllUsers
if (-not $rootKey) {
    Write-Error "Failed to open $(if ($AllUsers) { 'HKLM' } else { 'HKCU' })\Software\Classes for write."
    exit 1
}

$Report = if ($AllUsers) { New-HKLMReport } else { $null }

foreach ($t in $Targets) {
    $itemSubPath    = Get-ItemSubPath -Target $t -KeyName $KeyName
    $commandSubPath = "$itemSubPath\command"

    if ($Revert) {
        try {
            $rootKey.DeleteSubKeyTree($itemSubPath, $false)
            Write-Host "Removed $t context item at: ${itemSubPath}"
            if ($Report) { $Report.Succeeded += $t }
        } catch {
            if ($_.Exception -and ($_.Exception.Message -notmatch 'cannot find the subkey')) {
                Write-Warning "Failed to remove $t at ${itemSubPath}: $($_.Exception.Message)"
                if ($Report) {
                    $Report.Failed        += $t
                    $Report.FailedDetails += "${t}: $($_.Exception.Message)"
                }
            } else {
                Write-Host "Nothing to remove for $t at: ${itemSubPath}"
                if ($Report) { $Report.Succeeded += $t }
            }
        }
        continue
    }

    try {
        $itemKey    = $rootKey.CreateSubKey($itemSubPath)    # writable RegistryKey
        $commandKey = $rootKey.CreateSubKey($commandSubPath)

        if (-not $itemKey -or -not $commandKey) {
            throw "CreateSubKey returned null for '${itemSubPath}' or '${commandSubPath}'."
        }

        # Menu text (default + MUIVerb)
        $itemKey.SetValue('', $Title, [Microsoft.Win32.RegistryValueKind]::String)
        $itemKey.SetValue('MUIVerb', $Title, [Microsoft.Win32.RegistryValueKind]::String)

        # Optional icon
        if ($Icon) {
            $itemKey.SetValue('Icon', $Icon, [Microsoft.Win32.RegistryValueKind]::String)
        }

        # Command line
        $argTpl = if ($t -eq 'Background') { $BackgroundArguments } else { $Arguments }
        $cmd    = Build-CommandLine -ExePath $CommandPath -ArgTemplate $argTpl
        $commandKey.SetValue('', $cmd, [Microsoft.Win32.RegistryValueKind]::String)

        $commandKey.Close()
        $itemKey.Close()

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

if ($Report) { Write-HKLMReport -Report $Report }

$rootKey.Close()
if ($RestartExplorer) { Restart-Explorer }
