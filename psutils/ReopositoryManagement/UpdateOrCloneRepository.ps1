# PowerShell Script for Updating or Cloning a Repository

param (
    [string]$Directory,
    [string]$Ref,
    [string]$Address,
    [string]$Remote = "origin",
    [string]$AddressSecondary,
    [string]$RemoteSecondary = "mirror",
    [string]$AddressTertiary,
    [string]$RemoteTertiary = "local",
    [switch]$ThrowOnErrors,
    [switch]$DefaultFromVars,
    [switch]$Execute,
    [switch]$ParamsToVars
)

$ParameterGlobalVariablePrefix = "Repository"

function IsGitRepository {
    param ([string]$directoryPath)
    while ($directoryPath -and (Test-Path $directoryPath)) {
        if (Test-Path "$directoryPath\.git") {
            return $true
        }
        $directoryPath = Split-Path $directoryPath -Parent
    }
    return $false
}

function GetGitRepositoryRoot {
    param ([string]$directoryPath)
    while ($directoryPath -and (Test-Path $directoryPath)) {
        if (Test-Path "$directoryPath\.git") {
            return $directoryPath
        }
        $directoryPath = Split-Path $directoryPath -Parent
    }
    return $null
}

function GetGitRemoteAddress {
    param ([string]$directoryPath, [string]$remoteName)
    $rootDir = GetGitRepositoryRoot $directoryPath
    if (-not $rootDir) { return $null }
    try {
        return (git -C $rootDir remote get-url $remoteName 2>$null)
    } catch { return $null }
}

function GetGitRepositoryName {
    param ([string]$repositoryAddress)
    $name = Split-Path $repositoryAddress -Leaf
    return $name -replace "\.git$", ""
}

function HandleErrors {
    param ([string]$message)
    Write-Host "ERROR: $message" -ForegroundColor Red
    if ($ThrowOnErrors) { throw $message }
}

function UpdateOrCloneRepository {
    param (
        [string]$directory,
        [string]$ref,
        [string]$address,
        [string]$remote = "origin",
        [string]$addressSecondary,
        [string]$remoteSecondary = "mirror",
        [string]$addressTertiary,
        [string]$remoteTertiary = "local",
        [switch]$ThrowOnErrors,
        [switch]$DefaultFromVars
    )
    
    if (-not $directory -and $address) {
        $directory = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) (GetGitRepositoryName $address)
    }

    if ($directory -and -not (Test-Path $directory)) {
        Write-Host "Creating directory: $directory"
        New-Item -ItemType Directory -Path $directory | Out-Null
    }

    if (Test-Path $directory -and (IsGitRepository $directory)) {
        Write-Host "Repository found in $directory. Checking remote consistency..."
        $existingRemote = GetGitRemoteAddress $directory $remote
        if ($address -and $existingRemote -and ($existingRemote -ne $address)) {
            HandleErrors "Repository directory ($directory) contains a different Git repository than specified."
        }
        Write-Host "Fetching latest updates..."
        git -C $directory fetch --all
    } else {
        if (-not $address) {
            HandleErrors "No repository address provided and directory is empty. Cannot proceed."
        }
        Write-Host "Cloning repository into $directory..."
        git clone --origin $remote $address $directory
    }
    
    if ($addressSecondary) {
        Write-Host "Setting secondary remote ($remoteSecondary) to $addressSecondary"
        git -C $directory remote add $remoteSecondary $addressSecondary 2>$null || git -C $directory remote set-url $remoteSecondary $addressSecondary
    }

    if ($addressTertiary) {
        Write-Host "Setting tertiary remote ($remoteTertiary) to $addressTertiary"
        git -C $directory remote add $remoteTertiary $addressTertiary 2>$null || git -C $directory remote set-url $remoteTertiary $addressTertiary
    }

    if ($ref) {
        Write-Host "Checking out reference: $ref"
        try {
            git -C $directory checkout $ref 2>$null || (git -C $directory fetch $remote && git -C $directory checkout -b $ref "$remote/$ref")
        } catch {
            HandleErrors "Failed to checkout reference: $ref. Ensure it exists."
        }
    }
    
    Write-Host "Repository is up to date."
}

if ($Execute -or ($PSBoundParameters.ContainsKey('Address') -or $PSBoundParameters.ContainsKey('Directory'))) {
    UpdateOrCloneRepository -directory $Directory -ref $Ref -address $Address -remote $Remote -addressSecondary $AddressSecondary -remoteSecondary $RemoteSecondary -addressTertiary $AddressTertiary -remoteTertiary $RemoteTertiary -ThrowOnErrors:$ThrowOnErrors -DefaultFromVars:$DefaultFromVars
}
