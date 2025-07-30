# BackupDir.ps1 - Refined and Robustified

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

function Get-CopyName {
    param(
        [string]$BaseName,
        [int]$Index,
        [int]$Digits
    )
    return "$BaseName" + "_" + $Index.ToString("D$Digits")
}

function Remove-ExcessCopies {
    param(
        [string]$ParentDir,
        [string]$BaseName,
        [int]$NumCopies,
        [int]$MinDigits,
        [bool]$DryRun,
        [bool]$VerboseMode
    )

    $maxExisting = 0
    while ($true) {
        $testName = Get-CopyName -BaseName $BaseName -Index ($maxExisting + 1) -Digits $MinDigits
        $testPath = Join-Path $ParentDir $testName
        if (Test-Path $testPath) {
            $maxExisting++
        } else {
            break
        }
    }

    for ($i = $NumCopies + 1; $i -le $maxExisting; $i++) {
        $redundantName = Get-CopyName -BaseName $BaseName -Index $i -Digits $MinDigits
        $redundantPath = Join-Path $ParentDir $redundantName
        if (Test-Path $redundantPath) {
            if ($VerboseMode) { Write-Output "Removing redundant backup copy: $redundantPath" }
            if (-not $DryRun) {
                Remove-Item -Path $redundantPath -Recurse -Force
            }
        }
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

    if (-not $DryRun -and -not (Test-Path -Path $Destination)) {
        if ($VerboseMode) { Write-Output "Creating destination root: $Destination" }
        New-Item -Path $Destination -ItemType Directory -Force | Out-Null
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
            if ((Test-Path $targetPath) -and $OverwriteOlder) {
                $srcTime = $_.LastWriteTime
                $dstItem = Get-Item $targetPath
                $dstTime = $dstItem.LastWriteTime
                $srcSize = $_.Length
                $dstSize = $dstItem.Length

                if (($srcTime -eq $dstTime -and $srcSize -eq $dstSize) -or ($dstTime -gt $srcTime)) {
                    $copyFile = $false
                }
            }
            if ($copyFile) {
                if ($VerboseMode) { Write-Output "Copying file: $_ -> $targetPath" }
                if (-not $DryRun) {
                    Copy-Item $_.FullName -Destination $targetPath -Force
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
    $dirBase = Split-Path -Leaf $TargetDir
    $parentDir = Split-Path -Parent $TargetDir

    Remove-ExcessCopies -ParentDir $parentDir -BaseName $dirBase -NumCopies $NumCopies -MinDigits $MinDigits -DryRun:$DryRun -VerboseMode:$VerboseMode

    for ($i = $NumCopies; $i -ge 1; $i--) {
        $srcName = if ($i -eq 1) { $dirBase } else { Get-CopyName -BaseName $dirBase -Index ($i - 1) -Digits $MinDigits }
        $dstName = Get-CopyName -BaseName $dirBase -Index $i -Digits $MinDigits
        $srcPath = Join-Path $parentDir $srcName
        $dstPath = Join-Path $parentDir $dstName

        if (Test-Path $srcPath) {
            if ($VerboseMode) { Write-Output "Renaming $srcPath -> $dstPath" }
            if (-not $DryRun) {
                Rename-Item -Path $srcPath -NewName (Split-Path -Leaf $dstPath) -Force
            }
        }
    }

    if ($VerboseMode) { Write-Output "Copying fresh source to $TargetDir" }
    Copy-DirectoryRecursive -Source $SourceDir -Destination $TargetDir -OverwriteOlder:$false -KeepNonexistent:$false -DryRun:$DryRun -VerboseMode:$VerboseMode

    Remove-ExcessCopies -ParentDir $parentDir -BaseName $dirBase -NumCopies $NumCopies -MinDigits $MinDigits -DryRun:$DryRun -VerboseMode:$VerboseMode
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

if ($IsVerbose) {
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
