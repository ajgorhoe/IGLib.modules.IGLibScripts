
<#
.SYNOPSIS
    Script file for backing up an individual directory

.DESCRIPTION
    To be added.

.NOTES
    Copyright © Igor Grešovnik.
    Part of IGLib: https://github.com/ajgorhoe/IGLib.modules.IGLibScripts
	License:
	https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/LICENSE.md

.EXAMPLE
    BackupDir c:\users\admin\mail e:\backups\users\admin\mail -NumCopies 2 -MinDigits 2


.EXAMPLE
    BackupDir c:\users\admin\mail e:\backups\users\admin\mail

.EXAMPLE
    BackupDir c:\users\admin\mail e:\backups\users\admin\mail -InPlace

.EXAMPLE
    BackupDir c:\users\admin\mail e:\backups\users\admin\mail -InPlace -OverwriteOlder `-KeepNonexistent`
    
#>

param(
    [Parameter(Mandatory = $true)]
    [string]$SourceDir,

    [Parameter(Mandatory = $true)]
    [string]$DestDir,

    [switch]$InPlace,
    [switch]$OverwriteOlder,
    [switch]$KeepNonexistent,

    [int]$NumCopies = 0,
    [int]$MinDigits = 2
)

# Constants
$DefaultNumCopies = 0
$DefaultMinDigits = 2

function Show-ErrorAndExit {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Copy-DirectoryRecursive {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$OverwriteOlder = $false
    )

    if (-not (Test-Path -Path $Destination)) {
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
    }

    Get-ChildItem -Path $Source -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($Source.Length).TrimStart('\')
        $destFile = Join-Path $Destination $relativePath
        $destDir = Split-Path $destFile -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }
        if (-not (Test-Path $destFile) -or
            ($OverwriteOlder -and
                ($_.LastWriteTime -gt (Get-Item $destFile).LastWriteTime -or
                ($_.LastWriteTime -eq (Get-Item $destFile).LastWriteTime -and $_.Length -ne (Get-Item $destFile).Length)))) {
            Copy-Item -Path $_.FullName -Destination $destFile -Force
        }
    }
}

function Remove-NonexistentItems {
    param(
        [string]$Source,
        [string]$Destination
    )
    $sourceItems = Get-ChildItem -Path $Source -Recurse | ForEach-Object { $_.FullName.Substring($Source.Length).TrimStart('\') }
    $destItems = Get-ChildItem -Path $Destination -Recurse | ForEach-Object { $_.FullName.Substring($Destination.Length).TrimStart('\') }
    $toRemove = $destItems | Where-Object { $_ -notin $sourceItems }
    foreach ($item in $toRemove) {
        $fullPath = Join-Path $Destination $item
        Remove-Item -Path $fullPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-CopyName {
    param(
        [string]$BaseName,
        [int]$Index,
        [int]$Digits
    )
    return "$BaseName" + "_" + ($Index.ToString("D$Digits"))
}

function Get-ExistingCopies {
    param(
        [string]$BasePath,
        [string]$BaseName,
        [int]$Digits
    )
    $copies = @{}
    $regex = [regex]::Escape($BaseName) + "_(\d{$Digits,})$"
    Get-ChildItem -Path $BasePath -Directory | ForEach-Object {
        if ($_.Name -match $regex) {
            $copies[[int]$matches[1]] = $_.FullName
        }
    }
    return $copies
}

function Perform-InPlaceCopy {
    if (-not (Test-Path -Path $DestDir)) {
        Copy-DirectoryRecursive -Source $SourceDir -Destination $DestDir -OverwriteOlder:$false
        return
    }
    Copy-DirectoryRecursive -Source $SourceDir -Destination $DestDir -OverwriteOlder:$OverwriteOlder
    if (-not $KeepNonexistent) {
        Remove-NonexistentItems -Source $SourceDir -Destination $DestDir
    }
}

function Perform-CompleteCopy {
    $parent = Split-Path -Parent $DestDir
    $baseName = Split-Path -Leaf $DestDir

    $copies = Get-ExistingCopies -BasePath $parent -BaseName $baseName -Digits $MinDigits
    $maxIndex = 0
    if ($copies.Keys.Count -gt 0) {
        $maxIndex = ($copies.Keys | Measure-Object -Maximum).Maximum
    }

    # Promote copies (start from highest)
    for ($i = $maxIndex; $i -ge 1; $i--) {
        $oldPath = Get-CopyName -BaseName $baseName -Index $i -Digits $MinDigits
        $oldFullPath = Join-Path $parent $oldPath
        $newPath = Get-CopyName -BaseName $baseName -Index ($i + 1) -Digits $MinDigits
        $newFullPath = Join-Path $parent $newPath
        if (Test-Path $oldFullPath) {
            Rename-Item -Path $oldFullPath -NewName (Split-Path $newFullPath -Leaf)
        }
    }

    # Promote primary backup
    if (Test-Path $DestDir) {
        $newName = Get-CopyName -BaseName $baseName -Index 1 -Digits $MinDigits
        Rename-Item -Path $DestDir -NewName $newName
    }

    # Copy fresh backup
    Copy-DirectoryRecursive -Source $SourceDir -Destination $DestDir

    # Cleanup older backups
    $currentCopies = Get-ExistingCopies -BasePath $parent -BaseName $baseName -Digits $MinDigits
    $removeThreshold = $NumCopies + 1
    foreach ($k in $currentCopies.Keys | Sort-Object -Descending) {
        if ($k -ge $removeThreshold) {
            Remove-Item -Path $currentCopies[$k] -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# Entry point

if (-not (Test-Path $SourceDir)) {
    Show-ErrorAndExit "Source directory to be backed up does not exist: \"$SourceDir\""
}

if ($InPlace) {
    Perform-InPlaceCopy
} else {
    Perform-CompleteCopy
}
