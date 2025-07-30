# BackupDir.ps1 - Refined

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$SourceDir,

    [Parameter(Mandatory=$true, Position=1)]
    [string]$DestDir,

    [switch]$InPlace,
    [switch]$OverwriteOlder,
    [switch]$KeepNonexistent,
    [switch]$DryRun,
    [int]$NumCopies = 0,
    [int]$MinDigits = 2,
    [switch]$Execute,
    [switch]$IsVerbose
)

function Get-CanonicalAbsolutePath {
    param([string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetFullPath($Path)
    } else {
        return [System.IO.Path]::GetFullPath((Join-Path -Path (Get-Location) -ChildPath $Path))
    }
}

function Copy-DirectoryRecursive {
    param(
        [string]$Source,
        [string]$Destination,
        [bool]$OverwriteOlder,
        [bool]$KeepNonexistent,
        [bool]$DryRun,
        [bool]$VerboseMode
    )

    $copiedFiles = 0
    if (-not $DryRun) {
        if (-not (Test-Path -Path $Destination)) {
            if ($VerboseMode) { Write-Output "Creating destination root: $Destination" }
            New-Item -Path $Destination -ItemType Directory -Force | Out-Null
        }
    }

    Get-ChildItem -Path $Source -Recurse -Force | ForEach-Object {
        $relativePath = $_.FullName.Substring($Source.Length).TrimStart('\')
        $targetPath = Join-Path -Path $Destination -ChildPath $relativePath

        if ($_.PSIsContainer) {
            if (-not (Test-Path $targetPath)) {
                if ($VerboseMode) { Write-Output "Creating directory: $targetPath" }
                if (-not $DryRun) {
                    New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
                }
            }
        } else {
            $copyFile = $true
            if (Test-Path $targetPath) {
                if ($OverwriteOlder) {
                    $srcTime = $_.LastWriteTime
                    $dstItem = Get-Item $targetPath
                    $dstTime = $dstItem.LastWriteTime
                    $srcSize = $_.Length
                    $dstSize = $dstItem.Length

                    if ($srcTime -eq $dstTime -and $srcSize -eq $dstSize) {
                        $copyFile = $false
                    } elseif ($dstTime -gt $srcTime) {
                        $copyFile = $false
                    }
                }
            }
            if ($copyFile) {
                if ($VerboseMode) { Write-Output "Copying file: $_ -> $targetPath" }
                if (-not $DryRun) {
                    Copy-Item $_.FullName -Destination $targetPath -Force
                    $copiedFiles++
                }
            }
        }
    }

    if (-not $KeepNonexistent) {
        Get-ChildItem -Path $Destination -Recurse -Force | ForEach-Object {
            $relativePath = $_.FullName.Substring($Destination.Length).TrimStart('\')
            $sourcePath = Join-Path -Path $Source -ChildPath $relativePath
            if (-not (Test-Path $sourcePath)) {
                if ($VerboseMode) { Write-Output "Removing extra item: $_" }
                if (-not $DryRun) {
                    Remove-Item -Path $_.FullName -Force -Recurse
                }
            }
        }
    }
}

function Perform-InPlaceCopy {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [bool]$OverwriteOlder,
        [bool]$KeepNonexistent,
        [bool]$DryRun,
        [bool]$VerboseMode
    )
    if ($VerboseMode) { Write-Output "Starting in-place copy..." }
    Copy-DirectoryRecursive -Source $SourceDir -Destination $TargetDir -OverwriteOlder:$OverwriteOlder -KeepNonexistent:$KeepNonexistent -DryRun:$DryRun -VerboseMode:$VerboseMode
}

function Perform-CompleteCopy {
    param(
        [string]$SourceDir,
        [string]$TargetDir,
        [int]$NumCopies,
        [int]$MinDigits,
        [bool]$DryRun,
        [bool]$VerboseMode
    )
    if ($VerboseMode) { Write-Output "Starting complete copy..." }

    $dirBase = Split-Path -Leaf $TargetDir
    $parentDir = Split-Path -Parent $TargetDir

    for ($i = $NumCopies; $i -ge 1; $i--) {
        $suffixOld = "_" + ($i - 1).ToString("D$MinDigits")
        $suffixNew = "_" + $i.ToString("D$MinDigits")

        $oldPath = if ($i -eq 1) { $TargetDir } else { Join-Path $parentDir ("$dirBase$suffixOld") }
        $newPath = Join-Path $parentDir ("$dirBase$suffixNew")

        if (Test-Path $oldPath) {
            if ($VerboseMode) { Write-Output "Renaming $oldPath -> $newPath" }
            if (-not $DryRun) {
                Rename-Item -Path $oldPath -NewName (Split-Path -Leaf $newPath) -Force
            }
        }
    }

    if ($VerboseMode) { Write-Output "Copying fresh source to $TargetDir" }
    Copy-DirectoryRecursive -Source $SourceDir -Destination $TargetDir -OverwriteOlder:$false -KeepNonexistent:$false -DryRun:$DryRun -VerboseMode:$VerboseMode

    $redundantCopy = Join-Path $parentDir ("$dirBase_" + ($NumCopies + 1).ToString("D$MinDigits"))
    if (Test-Path $redundantCopy) {
        if ($VerboseMode) { Write-Output "Removing redundant copy: $redundantCopy" }
        if (-not $DryRun) {
            Remove-Item -Path $redundantCopy -Recurse -Force
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

    $SourceDirAbs = Get-CanonicalAbsolutePath $SourceDir
    $DestParentDirAbs = Get-CanonicalAbsolutePath $DestDir
    $BackupName = Split-Path -Leaf $SourceDirAbs
    $BackupDestDir = Join-Path $DestParentDirAbs $BackupName

    if (-not (Test-Path -Path $SourceDirAbs)) {
        Write-Error "Source directory does not exist: $SourceDirAbs"
        return
    }

    if ($VerboseMode) {
        Write-Output "BackupDir script invoked."
        Write-Output "Parameters:"
        Write-Output "  SourceDir: $SourceDirAbs"
        Write-Output "  DestDir (Parent): $DestParentDirAbs"
        Write-Output "  Final TargetDir: $BackupDestDir"
        Write-Output "  InPlace: $InPlace"
        Write-Output "  OverwriteOlder: $OverwriteOlder"
        Write-Output "  KeepNonexistent: $KeepNonexistent"
        Write-Output "  DryRun: $DryRun"
        Write-Output "  NumCopies: $NumCopies"
        Write-Output "  MinDigits: $MinDigits"
    }

    if ($InPlace) {
        Perform-InPlaceCopy -SourceDir $SourceDirAbs -TargetDir $BackupDestDir -OverwriteOlder:$OverwriteOlder -KeepNonexistent:$KeepNonexistent -DryRun:$DryRun -VerboseMode:$VerboseMode
    } else {
        Perform-CompleteCopy -SourceDir $SourceDirAbs -TargetDir $BackupDestDir -NumCopies:$NumCopies -MinDigits:$MinDigits -DryRun:$DryRun -VerboseMode:$VerboseMode
    }
}

# Main execution block
if ($IsVerbose -or $true) {
    Write-Output "\nScript input parameters:"
    Write-Output "  SourceDir: $SourceDir"
    Write-Output "  DestDir: $DestDir"
    Write-Output "  InPlace: $InPlace"
    Write-Output "  OverwriteOlder: $OverwriteOlder"
    Write-Output "  KeepNonexistent: $KeepNonexistent"
    Write-Output "  DryRun: $DryRun"
    Write-Output "  NumCopies: $NumCopies"
    Write-Output "  MinDigits: $MinDigits"
    Write-Output "  Execute: $Execute"
    Write-Output "  IsVerbose: $IsVerbose"
}

if ($Execute -or ($PSBoundParameters.ContainsKey('Execute') -eq $false -and $SourceDir -and $DestDir)) {
    BackupDir -SourceDir $SourceDir -DestDir $DestDir -InPlace:$InPlace -OverwriteOlder:$OverwriteOlder -KeepNonexistent:$KeepNonexistent -DryRun:$DryRun -NumCopies:$NumCopies -MinDigits:$MinDigits -VerboseMode:$IsVerbose
} else {
    if ($IsVerbose) { Write-Output "BackupDir function defined but not executed (Execute=$Execute)." }
}
