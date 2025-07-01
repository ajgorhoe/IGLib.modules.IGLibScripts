param(
    [string]$SourceDir,
    [string]$DestDir,

    [switch]$InPlace,
    [switch]$OverwriteOlder,
    [switch]$KeepNonexistent,
    [switch]$DryRun,
    [switch]$Execute,

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
        [bool]$OverwriteOlder = $false,
        [bool]$VerboseMode = $false,
        [bool]$DryRun = $false
    )

    if (-not (Test-Path -Path $Destination)) {
        if ($DryRun) {
            Write-Output "[DryRun] Would create directory: $Destination"
        } else {
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }
    }

    Get-ChildItem -Path $Source -Recurse -File | ForEach-Object {
        $relativePath = $_.FullName.Substring($Source.Length).TrimStart('\')
        $destFile = Join-Path $Destination $relativePath
        $destDir = Split-Path $destFile -Parent

        if (-not (Test-Path $destDir)) {
            if ($DryRun) {
                Write-Output "[DryRun] Would create directory: $destDir"
            } else {
                New-Item -Path $destDir -ItemType Directory -Force | Out-Null
            }
        }

        $shouldCopy = $true
        if (Test-Path $destFile) {
            if ($OverwriteOlder) {
                $destItem = Get-Item $destFile
                if ($_.LastWriteTime -lt $destItem.LastWriteTime -or
                    ($_.LastWriteTime -eq $destItem.LastWriteTime -and $_.Length -eq $destItem.Length)) {
                    $shouldCopy = $false
                }
            }
        }

        if ($shouldCopy) {
            if ($DryRun) {
                Write-Output "[DryRun] Would copy: $_ => $destFile"
            } else {
                Copy-Item -Path $_.FullName -Destination $destFile -Force
                if ($VerboseMode) {
                    Write-Verbose "Copied: $_ => $destFile"
                }
            }
        }
    }
}

function Remove-NonexistentItems {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$VerboseMode = $false,
        [bool]$DryRun = $false
    )
    $sourceItems = Get-ChildItem -Path $Source -Recurse | ForEach-Object { $_.FullName.Substring($Source.Length).TrimStart('\') }
    $destItems = Get-ChildItem -Path $Destination -Recurse | ForEach-Object { $_.FullName.Substring($Destination.Length).TrimStart('\') }
    $toRemove = $destItems | Where-Object { $_ -notin $sourceItems }
    foreach ($item in $toRemove) {
        $fullPath = Join-Path $Destination $item
        if ($DryRun) {
            Write-Output "[DryRun] Would remove: $fullPath"
        } else {
            Remove-Item -Path $fullPath -Recurse -Force -ErrorAction SilentlyContinue
            if ($VerboseMode) {
                Write-Verbose "Removed: $fullPath"
            }
        }
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
    $regex = [regex]::Escape($BaseName) + "_(\\d{$Digits,})$"
    Get-ChildItem -Path $BasePath -Directory | ForEach-Object {
        if ($_.Name -match $regex) {
            $copies[[int]$matches[1]] = $_.FullName
        }
    }
    return $copies
}

function Perform-InPlaceCopy {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [bool]$OverwriteOlder,
        [bool]$KeepNonexistent,
        [bool]$VerboseMode,
        [bool]$DryRun
    )

    if (-not (Test-Path -Path $DestDir)) {
        Copy-DirectoryRecursive -Source $SourceDir -Destination $DestDir -OverwriteOlder:$false -VerboseMode:$VerboseMode -DryRun:$DryRun
        return
    }
    Copy-DirectoryRecursive -Source $SourceDir -Destination $DestDir -OverwriteOlder:$OverwriteOlder -VerboseMode:$VerboseMode -DryRun:$DryRun
    if (-not $KeepNonexistent) {
        Remove-NonexistentItems -Source $SourceDir -Destination $DestDir -VerboseMode:$VerboseMode -DryRun:$DryRun
    }
}

function Perform-CompleteCopy {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [int]$NumCopies,
        [int]$MinDigits,
        [bool]$VerboseMode,
        [bool]$DryRun
    )

    $parent = Split-Path -Parent $DestDir
    $baseName = Split-Path -Leaf $DestDir

    $copies = Get-ExistingCopies -BasePath $parent -BaseName $baseName -Digits $MinDigits
    $maxIndex = 0
    if ($copies.Keys.Count -gt 0) {
        $maxIndex = ($copies.Keys | Measure-Object -Maximum).Maximum
    }

    for ($i = $maxIndex; $i -ge 1; $i--) {
        $oldPath = Get-CopyName -BaseName $baseName -Index $i -Digits $MinDigits
        $oldFullPath = Join-Path $parent $oldPath
        $newPath = Get-CopyName -BaseName $baseName -Index ($i + 1) -Digits $MinDigits
        $newFullPath = Join-Path $parent $newPath
        if (Test-Path $oldFullPath) {
            if ($DryRun) {
                Write-Output "[DryRun] Would rename: $oldFullPath => $newFullPath"
            } else {
                Rename-Item -Path $oldFullPath -NewName (Split-Path $newFullPath -Leaf)
                if ($VerboseMode) {
                    Write-Verbose "Renamed: $oldFullPath => $newFullPath"
                }
            }
        }
    }

    if (Test-Path $DestDir) {
        $newName = Get-CopyName -BaseName $baseName -Index 1 -Digits $MinDigits
        $newFullPath = Join-Path $parent $newName
        if ($DryRun) {
            Write-Output "[DryRun] Would rename: $DestDir => $newFullPath"
        } else {
            Rename-Item -Path $DestDir -NewName $newName
            if ($VerboseMode) {
                Write-Verbose "Renamed: $DestDir => $newFullPath"
            }
        }
    }

    Copy-DirectoryRecursive -Source $SourceDir -Destination $DestDir -OverwriteOlder:$false -VerboseMode:$VerboseMode -DryRun:$DryRun

    $currentCopies = Get-ExistingCopies -BasePath $parent -BaseName $baseName -Digits $MinDigits
    $removeThreshold = $NumCopies + 1
    foreach ($k in $currentCopies.Keys | Sort-Object -Descending) {
        if ($k -ge $removeThreshold) {
            if ($DryRun) {
                Write-Output "[DryRun] Would delete: $($currentCopies[$k])"
            } else {
                Remove-Item -Path $currentCopies[$k] -Recurse -Force -ErrorAction SilentlyContinue
                if ($VerboseMode) {
                    Write-Verbose "Deleted: $($currentCopies[$k])"
                }
            }
        }
    }
}

function BackupDir {
    param(
        [string]$SourceDir,
        [string]$DestDir,
        [bool]$InPlace,
        [bool]$OverwriteOlder,
        [bool]$KeepNonexistent,
        [bool]$DryRun,
        [int]$NumCopies,
        [int]$MinDigits,
        [bool]$VerboseMode
    )

    if (-not (Test-Path $SourceDir)) {
        Show-ErrorAndExit "Source directory to be backed up does not exist: \"$SourceDir\""
    }

    if ($InPlace) {
        Perform-InPlaceCopy -SourceDir $SourceDir -DestDir $DestDir -OverwriteOlder:$OverwriteOlder -KeepNonexistent:$KeepNonexistent -VerboseMode:$VerboseMode -DryRun:$DryRun
    } else {
        Perform-CompleteCopy -SourceDir $SourceDir -DestDir $DestDir -NumCopies:$NumCopies -MinDigits:$MinDigits -VerboseMode:$VerboseMode -DryRun:$DryRun
    }
}

# Determine verbosity
$IsVerbose = $VerbosePreference -eq 'Continue'

# Verbose parameter printout
if ($IsVerbose) {
    Write-Output \"BackupDir script invoked.\"
    Write-Output \"Parameters:\"
    Write-Output \"  SourceDir: $SourceDir\"
    Write-Output \"  DestDir: $DestDir\"
    Write-Output \"  InPlace: $InPlace\"
    Write-Output \"  OverwriteOlder: $OverwriteOlder\"
    Write-Output \"  KeepNonexistent: $KeepNonexistent\"
    Write-Output \"  DryRun: $DryRun\"
    Write-Output \"  NumCopies: $NumCopies\"
    Write-Output \"  MinDigits: $MinDigits\"
    Write-Output \"  Execute: $Execute\"
} else {
    Write-Output "`nThe IsVerbose is NOT true!`n."
}

# Determine if we should execute
$shouldExecute = $false
if ($Execute.IsPresent) {
    $shouldExecute = $Execute
} elseif ($SourceDir -and $DestDir) {
    $shouldExecute = $true
}

# Perform backup if applicable
if ($shouldExecute) {
    BackupDir -SourceDir:$SourceDir -DestDir:$DestDir -InPlace:$InPlace -OverwriteOlder:$OverwriteOlder -KeepNonexistent:$KeepNonexistent -DryRun:$DryRun -NumCopies:$NumCopies -MinDigits:$MinDigits -VerboseMode:$IsVerbose
}
