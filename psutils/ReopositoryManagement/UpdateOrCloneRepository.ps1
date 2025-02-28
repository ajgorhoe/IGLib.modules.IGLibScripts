# UpdateOrCloneRepository.ps1
# A Windows PowerShell–compatible script for updating or cloning a Git repository.

# Note: This version avoids using logical operators (&&, ||) not supported in Windows PowerShell.
# It also splits commands into multiple lines for clarity and error handling.

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

###############################################################################
# Constants
###############################################################################

# Prefix used for setting/retrieving global variables
$ParameterGlobalVariablePrefix = "Repository"

# Default values
$DefaultRemote          = "origin"
$DefaultRemoteSecondary = "mirror"
$DefaultRemoteTertiary  = "local"

###############################################################################
# Utility Functions
###############################################################################

function Write-Info {
    param([string]$Message)
    Write-Host "Info: $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "Warning: $Message" -ForegroundColor Yellow
}

function Write-ErrorReport {
    param([string]$Message)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    if ($ThrowOnErrors) {
        throw $Message
    }
}

function IsGitRepository {
    param ([string]$directoryPath)
    # This checks upward if the path is nested within a repository.
    while ($directoryPath -and (Test-Path $directoryPath)) {
        if (Test-Path (Join-Path $directoryPath ".git")) {
            # We can do a quick check inside the .git folder:
            if (Test-Path (Join-Path $directoryPath ".git\\HEAD")) {
                return $true
            }
        }
        $parentPath = Split-Path $directoryPath -Parent
        if ($parentPath -eq $directoryPath) {
            break
        } else {
            $directoryPath = $parentPath
        }
    }
    return $false
}

function GetGitRepositoryRoot {
    param ([string]$directoryPath)
    while ($directoryPath -and (Test-Path $directoryPath)) {
        if (Test-Path (Join-Path $directoryPath ".git")) {
            # If we found .git, let's verify it is truly a Git repo:
            if (Test-Path (Join-Path $directoryPath ".git\\HEAD")) {
                return $directoryPath
            }
        }
        $parentPath = Split-Path $directoryPath -Parent
        if ($parentPath -eq $directoryPath) {
            return $null
        }
        $directoryPath = $parentPath
    }
    return $null
}

function GetGitRemoteAddress {
    param (
        [string]$directoryPath,
        [string]$remoteName
    )
    $rootDir = GetGitRepositoryRoot $directoryPath
    if (-not $rootDir) {
        return $null
    }
    try {
        $remoteUrl = git -C $rootDir remote get-url $remoteName 2>$null
        return $remoteUrl
    } catch {
        return $null
    }
}

function GetGitRepositoryName {
    param ([string]$repositoryAddress)
    if (-not $repositoryAddress) {
        return $null
    }
    $leaf = Split-Path $repositoryAddress -Leaf
    # Remove trailing .git if it exists
    $leaf = $leaf -replace "\\.git$", ""
    return $leaf
}

function EnsureFullPath {
    param ([string]$path)
    if ([IO.Path]::IsPathRooted($path)) {
        return (Resolve-Path -LiteralPath $path).Path
    } else {
        # Combine with script directory or current dir?
        # According to spec, if the script is run from the command line, use script's directory.
        # If in function context, let's default to current directory.
        if ($MyInvocation.MyCommand.Path) {
            $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
            return (Resolve-Path (Join-Path $scriptDir $path)).Path
        } else {
            return (Resolve-Path (Join-Path (Get-Location) $path)).Path
        }
    }
}

###############################################################################
# Main Function: UpdateOrCloneRepository
###############################################################################

function UpdateOrCloneRepository {
    param (
        [string]$directory,
        [string]$ref,
        [string]$address,
        [string]$remote = $DefaultRemote,
        [string]$addressSecondary,
        [string]$remoteSecondary = $DefaultRemoteSecondary,
        [string]$addressTertiary,
        [string]$remoteTertiary = $DefaultRemoteTertiary,
        [switch]$ThrowOnErrors,
        [switch]$DefaultFromVars
    )

    Write-Host ""    # blank line
    Write-Info "Updating or cloning a repository..."
    Write-Host "Parameters:" -ForegroundColor DarkCyan
    Write-Host "  directory:         $directory"
    Write-Host "  ref:               $ref"
    Write-Host "  address:           $address"
    Write-Host "  remote:            $remote"
    Write-Host "  addressSecondary:  $addressSecondary"
    Write-Host "  remoteSecondary:   $remoteSecondary"
    Write-Host "  addressTertiary:   $addressTertiary"
    Write-Host "  remoteTertiary:    $remoteTertiary"
    Write-Host "  ThrowOnErrors:     $ThrowOnErrors"
    Write-Host "  DefaultFromVars:   $DefaultFromVars"
    Write-Host ""    # blank line

    # Basic parameter handling repeated here, as required by specification.
    if (-not $directory -and $address) {
        $repoName = GetGitRepositoryName $address
        if ($repoName) {
            $directory = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) $repoName
        }
        else {
            $directory = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "Repo"
        }
    }

    if ($directory) {
        $directory = EnsureFullPath $directory
    }

    # If directory is specified but address is not, try to deduce address from existing remote.
    if (-not $address -and $directory) {
        if (Test-Path $directory -PathType Container -and (IsGitRepository $directory)) {
            $existingAddr = GetGitRemoteAddress $directory $remote
            if ($existingAddr) {
                $address = $existingAddr
                Write-Info "Deduced Address from existing remote '$remote': $address"
            }
        }
    }

    # Validate that we have either an existing repo or an address.
    if (-not $address -and $directory) {
        # Must be an existing repository to update.
        if (-not (Test-Path $directory)) {
            Write-ErrorReport "Directory $directory does not exist, and no address specified to clone from."
            return
        }
        else {
            if (-not (IsGitRepository $directory)) {
                Write-ErrorReport "Directory $directory is not a valid Git repository, and no address was specified."
                return
            }
        }
    }

    # If directory doesn't exist, create it so we can clone.
    if ($directory -and -not (Test-Path $directory)) {
        try {
            New-Item -ItemType Directory -Path $directory | Out-Null
            Write-Info "Created directory: $directory"
        }
        catch {
            Write-ErrorReport "Could not create directory: $directory"
            return
        }
    }

    # If directory exists and is non-empty, check if it's a valid Git repo.
    $dirExists = (Test-Path $directory -PathType Container)
    if ($dirExists) {
        $items = Get-ChildItem -Path $directory
        $isEmpty = ($items | Measure-Object).Count -eq 0
        if (-not $isEmpty) {
            if (-not (IsGitRepository $directory)) {
                Write-ErrorReport "Repository directory ($directory) is not empty and does not contain a valid Git repo."
                return
            }
            else {
                # Check remote consistency
                if ($address) {
                    $existingRemote = GetGitRemoteAddress $directory $remote
                    if ($existingRemote -and $existingRemote -ne $address) {
                        Write-ErrorReport \"Repository directory ($directory) has remote '$remote' set to '$existingRemote' but should be '$address'.\"
                        return
                    }
                }
            }
        }
    }

    # Clone if needed
    if ($address -and (!$dirExists -or ($dirExists -and $isEmpty))) {
        try {
            Write-Info \"Cloning repository from $address into $directory...\"
            git clone --origin $remote $address $directory
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorReport \"Failed to clone repository from $address into $directory.\"
                return
            }
        }
        catch {
            Write-ErrorReport \"Exception occurred while cloning from $address into $directory. $_\"
            return
        }
    }
    else {
        # If we already have the repository in place, fetch all.
        if ($address) {
            Write-Info \"Fetching all changes from $remote...\"
            try {
                git -C $directory fetch --all
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport \"Failed to fetch updates in $directory.\"
                    return
                }
            }
            catch {
                Write-ErrorReport \"Exception occurred while fetching in $directory: $_\"
                return
            }
        }
    }

    # Handle secondary remote
    if ($addressSecondary) {
        Write-Info \"Ensuring secondary remote ($remoteSecondary) points to $addressSecondary\"
        try {
            git -C $directory remote add $remoteSecondary $addressSecondary 2>$null
            if ($LASTEXITCODE -ne 0) {
                # If add fails, try set-url
                git -C $directory remote set-url $remoteSecondary $addressSecondary
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn \"Could not set secondary remote '$remoteSecondary' to '$addressSecondary'.\"
                }
                else {
                    Write-Warn \"Changed address of existing remote '$remoteSecondary' to '$addressSecondary'\"
                }
            }
            else {
                Write-Info \"Remote '$remoteSecondary' set to '$addressSecondary'\"
            }
        }
        catch {
            Write-ErrorReport \"Exception occurred while setting secondary remote. $_\"
            return
        }
    }

    # Handle tertiary remote
    if ($addressTertiary) {
        Write-Info \"Ensuring tertiary remote ($remoteTertiary) points to $addressTertiary\"
        try {
            git -C $directory remote add $remoteTertiary $addressTertiary 2>$null
            if ($LASTEXITCODE -ne 0) {
                # If add fails, try set-url
                git -C $directory remote set-url $remoteTertiary $addressTertiary
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn \"Could not set tertiary remote '$remoteTertiary' to '$addressTertiary'.\"
                }
                else {
                    Write-Warn \"Changed address of existing remote '$remoteTertiary' to '$addressTertiary'\"
                }
            }
            else {
                Write-Info \"Remote '$remoteTertiary' set to '$addressTertiary'\"
            }
        }
        catch {
            Write-ErrorReport \"Exception occurred while setting tertiary remote. $_\"
            return
        }
    }

    # Check out ref if specified
    if ($ref) {
        Write-Info \"Ensuring repository is checked out at reference '$ref'\"
        try {
            git -C $directory checkout $ref 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Info \"Local branch or ref '$ref' not found, attempting to fetch and create local branch.\"
                git -C $directory fetch $remote
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport \"Failed to fetch from remote '$remote'.\"
                    return
                }
                git -C $directory checkout -b $ref \"$remote/$ref\"
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport \"Failed to check out new branch '$ref' from remote '$remote'.\"
                    return
                }
                Write-Warn \"Current branch changed to '$ref' (new local branch tracking '$remote/$ref').\"
            }
            else {
                Write-Warn \"Repository switched to '$ref' (could be branch, tag, or commit).\"
            }
        }
        catch {
            Write-ErrorReport \"Failed to checkout reference '$ref'. $_\"
            return
        }
        # If it's a branch, we can pull to update
        # Check if ref is a branch or commit.
        # We'll just attempt a pull if it's a branch.
        $branches = (git -C $directory branch --show-current 2>$null).Trim()
        if ($branches -eq $ref) {
            Write-Info \"Pulling latest commits for branch '$ref' from '$remote'\"
            try {
                git -C $directory pull $remote $ref
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport \"Failed to pull latest changes for branch '$ref'.\"
                    return
                }
            }
            catch {
                Write-ErrorReport \"Exception occurred while pulling latest changes for branch '$ref'. $_\"
                return
            }
            Write-Info \"Repository in '$directory' is now updated to the latest commit of branch '$ref'\"
        }
        else {
            # We might be in a detached HEAD if ref is a tag or commit
            Write-Info \"The repository in '$directory' is checked out at '$ref'. (Possibly a detached HEAD).\"
            Write-Info \"Fetching from remote '$remote' in case the tag or commit was updated...\"
            try {
                git -C $directory fetch $remote --tags
                # There's not always a direct 'pull' for tags or commits
                # We'll assume we've updated the objects if the tag has changed.
            }
            catch {
                Write-Warn \"Could not fetch from remote '$remote' for tag or commit. $_\"
            }
        }
    }
    else {
        Write-Info \"No ref specified. Repository remains on its current branch/tag/commit.\"
    }

    Write-Info \"Repository is up to date in directory: $directory\"
}

###############################################################################
# Script logic for parameter resolution / global variables.
###############################################################################

function Resolve-ScriptParameters {
    # This function merges script-level parameters with global variable values if DefaultFromVars is set,
    # applies defaults, etc.

    # 1) If $DefaultFromVars is specified, for each parameter that is null or empty, try to get the global var.
    if ($DefaultFromVars) {
        foreach ($paramName in \"Directory\",\"Ref\",\"Address\",\"Remote\",\"AddressSecondary\",\"RemoteSecondary\",\"AddressTertiary\",\"RemoteTertiary\") {
            $scriptParamValue = (Get-Variable -Name $paramName -Scope 1 -ErrorAction SilentlyContinue).Value
            if (-not $scriptParamValue) {
                # We look if there's a global var with prefix
                $globalVarName = \"${ParameterGlobalVariablePrefix}${paramName.Substring(0,1).ToUpper()}${paramName.Substring(1)}\"
                $globalVal = (Get-Variable -Name $globalVarName -Scope Global -ErrorAction SilentlyContinue).Value
                if ($globalVal) {
                    Set-Variable -Name $paramName -Value $globalVal -Scope 1
                }
            }
        }
    }

    # 2) Apply default values if not set.
    if (-not $Remote) {
        $Remote = $DefaultRemote
    }
    if (-not $RemoteSecondary) {
        $RemoteSecondary = $DefaultRemoteSecondary
    }
    if (-not $RemoteTertiary) {
        $RemoteTertiary = $DefaultRemoteTertiary
    }

    # 3) Additional logic for deduce directory if address is present.
    # (Will be repeated in the main function too, as per specification.)
}

function Set-GlobalVarsIfRequested {
    if ($ParamsToVars) {
        foreach ($paramName in \"Directory\",\"Ref\",\"Address\",\"Remote\",\"AddressSecondary\",\"RemoteSecondary\",\"AddressTertiary\",\"RemoteTertiary\") {
            $globalVarName = \"${ParameterGlobalVariablePrefix}${paramName}\" # e.g. RepositoryDirectory
            $value = (Get-Variable -Name $paramName -Scope 1 -ErrorAction SilentlyContinue).Value
            if ($null -ne $value) {
                Set-Variable -Name $globalVarName -Value $value -Scope Global
            }
        }
    }
}

Resolve-ScriptParameters

# Decide whether to call the main function based on the logic described.
# 1) If $Execute is true, we run the main function unconditionally.
# 2) If $Execute is false, do not run the main function.
# 3) If $Execute is not specified, but Address or Directory are specified, we run the main function.

$shouldExecute = $false
if ($Execute.IsPresent) {
    if ($Execute) {
        $shouldExecute = $true
    }
    else {
        $shouldExecute = $false
    }
}
else {
    # If $Execute not specified, check if user provided Address or Directory.
    if ($PSBoundParameters.ContainsKey('Address') -or $PSBoundParameters.ContainsKey('Directory')) {
        $shouldExecute = $true
    }
}

Set-GlobalVarsIfRequested

if ($shouldExecute) {
    UpdateOrCloneRepository -directory $Directory `
                            -ref $Ref `
                            -address $Address `
                            -remote $Remote `
                            -addressSecondary $AddressSecondary `
                            -remoteSecondary $RemoteSecondary `
                            -addressTertiary $AddressTertiary `
                            -remoteTertiary $RemoteTertiary `
                            -ThrowOnErrors:$ThrowOnErrors `
                            -DefaultFromVars:$DefaultFromVars
}
