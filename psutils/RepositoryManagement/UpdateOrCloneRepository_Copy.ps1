# UpdateOrCloneRepository.ps1
# A Windows PowerShell–compatible script for updating or cloning a Git repository.

###############################################################################
# Script parameters
###############################################################################
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
# Constants & Defaults
###############################################################################

# Prefix used for setting/retrieving global variables
$ParameterGlobalVariablePrefix = "Repository"

# Default values
$DefaultRemote          = "origin"
$DefaultRemoteSecondary = "mirror"
$DefaultRemoteTertiary  = "local"

###############################################################################
# Logging & Error-Handling Helpers
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
    param([string]$Message, [switch]$throwOnErrors)
    Write-Host "ERROR: $Message" -ForegroundColor Red
    if ($throwOnErrors) {
        throw $Message
    }
}

###############################################################################
# Git Helper Functions
###############################################################################

function IsGitRepository {
    param ([string]$directoryPath)
    # Check upwards if the path is nested within a repository.
    while ($directoryPath -and (Test-Path $directoryPath)) {
        if (Test-Path (Join-Path $directoryPath ".git")) {
            # Quick check inside .git folder:
            if (Test-Path (Join-Path $directoryPath ".git\\HEAD")) {
                return $true
            }
        }
        $parentPath = Split-Path $directoryPath -Parent
        if ($parentPath -eq $directoryPath) { break }
        $directoryPath = $parentPath
    }
    return $false
}

function GetGitRepositoryRoot {
    param ([string]$directoryPath)
    while ($directoryPath -and (Test-Path $directoryPath)) {
        if (Test-Path (Join-Path $directoryPath ".git")) {
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
    if (-not $rootDir) { return $null }
    try {
        return git -C $rootDir remote get-url $remoteName 2>$null
    } catch {
        return $null
    }
}

function GetGitRepositoryName {
    param ([string]$repositoryAddress)
    if (-not $repositoryAddress) { return $null }
    $leaf = Split-Path $repositoryAddress -Leaf
    # Remove trailing .git if it exists
    $leaf = $leaf -replace "\.git$", ""
    return $leaf
}

###############################################################################
# Address Consistency Check
###############################################################################
# This function tries minimal normalization of addresses before comparison.

function CheckGitAddressConsistency {
    param (
        [string]$expected,
        [string]$actual
    )

    # Both empty => consistent
    if ([string]::IsNullOrWhiteSpace($expected) -and [string]::IsNullOrWhiteSpace($actual)) {
        return $true
    }
    # One empty, other not => inconsistent
    if ([string]::IsNullOrWhiteSpace($expected) -xor [string]::IsNullOrWhiteSpace($actual)) {
        return $false
    }

    # Minimal normalizations:
    # 1) Trim whitespace
    $exp = $expected.Trim()
    $act = $actual.Trim()

    # 2) If HTTP(S), remove trailing slash
    if ($exp -match '^https?://') { $exp = $exp.TrimEnd('/') }
    if ($act -match '^https?://') { $act = $act.TrimEnd('/') }

    # 3) If local path, attempt to resolve path if it exists
    function TryResolvePath([string]$p) {
        try {
            if (Test-Path $p) {
                # Return the resolved path (canonical)
                return (Resolve-Path -LiteralPath $p -ErrorAction Stop).Path
            }
            else {
                # Return the original
                return $p
            }
        } catch {
            return $p
        }
    }

    # A naive check for local paths: if it doesn't start with 'http' or 'ssh' or 'git@', treat as local
    if ($exp -notmatch '^(https?://|ssh://|git@)' ) { $exp = TryResolvePath $exp }
    if ($act -notmatch '^(https?://|ssh://|git@)' ) { $act = TryResolvePath $act }

    # 4) Case-insensitive comparison
    return ([string]::Equals($exp, $act, [System.StringComparison]::OrdinalIgnoreCase))
}

###############################################################################
# Path Helper
###############################################################################

function EnsureFullPath {
    param ([string]$path)
    if ([IO.Path]::IsPathRooted($path)) {
        # If it's already rooted, try to resolve
        try {
            return (Resolve-Path -LiteralPath $path -ErrorAction Stop).Path
        } catch {
            return $path  # Return raw path if it doesn't exist
        }
    }
    else {
        # Combine with script directory or current dir
        if ($MyInvocation.MyCommand.Path) {
            $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
            $combinedPath = Join-Path $scriptDir $path
        } else {
            $combinedPath = Join-Path (Get-Location) $path
        }
        try {
            return (Resolve-Path -LiteralPath $combinedPath -ErrorAction Stop).Path
        } catch {
            return $combinedPath
        }
    }
}

###############################################################################
# Main Function
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
        [switch]$throwOnErrors,       # Renamed to lower case
        [switch]$defaultFromVars      # Renamed to lower case
    )

    Write-Info "Updating or cloning a repository..."

    ############################################################################
    # (1) If $defaultFromVars, fill any missing parameters from global variables
    #     even if the function is called directly (not from the script).
    ############################################################################
    if ($defaultFromVars) {
        Write-Info "defaultFromVars is set (function scope). Checking for missing parameters..."
    
        # Use PascalCase param names to match global variable naming
        $paramList = 'Directory','Ref','Address','Remote','AddressSecondary','RemoteSecondary','AddressTertiary','RemoteTertiary'
    
        foreach ($p in $paramList) {
            # Did the caller explicitly specify this parameter?
            if (-not $PSBoundParameters.ContainsKey($p)) {
                # The user did NOT pass this parameter, so let's try to fill from global
                $upperParam   = $p.Substring(0,1).ToUpper() + $p.Substring(1)
                $globalVarName = "${ParameterGlobalVariablePrefix}${upperParam}"
    
                # Retrieve the function's current parameter value
                $currentVal = Get-Variable -Name $p -Scope 0 -ErrorAction SilentlyContinue
    
                # IMPORTANT: We must check $currentVal.Value, not $currentVal
                if ($currentVal -and $currentVal.Value) {
                    # The parameter is already set, so skip
                    Write-Info "  $p is already set, no override from global. Value: $($currentVal.Value)"
                    continue
                }
    
                # Show which global var we are about to check
                # Write-Info "  Checking global variable: $globalVarName"
                $globalVal = (Get-Variable -Name $globalVarName -Scope Global -ErrorAction SilentlyContinue).Value
                # Write-Info "  >> Global variable value: $globalVal"
    
                if ($globalVal) {
                    # We set the local function variable to the global value
                    Set-Variable -Name $p -Value $globalVal -Scope 0
                    Write-Info "  $p set from $globalVarName to $globalVal"
                }
                else {
                    Write-Info "  $p not set from global variable (it does not exist or is null)."
                }
            }
            else {
                Write-Info "  $p was explicitly provided by the caller, not using global variable."
            }
        }
    }
    

    ############################################################################
    # (2) Apply default values if not set
    ############################################################################
    if (-not $remote)           { $remote           = $DefaultRemote }
    if (-not $remoteSecondary)  { $remoteSecondary  = $DefaultRemoteSecondary }
    if (-not $remoteTertiary)   { $remoteTertiary   = $DefaultRemoteTertiary }

    ############################################################################
    # (3) Additional logic for deduce directory from address (if needed)
    ############################################################################
    if (-not $directory -and $address) {
        $repoName = GetGitRepositoryName $address
        if ($repoName) {
            $directory = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) $repoName
        } else {
            $directory = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "Repo"
        }
    }

    # Convert to full path
    if ($directory) {
        $directory = EnsureFullPath $directory
    }

    # If directory is specified but address is not, try to deduce from existing remote
    if (-not $address -and $directory) {
        if (Test-Path $directory -PathType Container -and (IsGitRepository $directory)) {
            $existingAddr = GetGitRemoteAddress $directory $remote
            if ($existingAddr) {
                $address = $existingAddr
                Write-Info "Deduced address from existing remote '$remote': $address"
            }
        }
    }

    ############################################################################
    # (4) Print final parameter values (after resolution), then validate
    ############################################################################
    Write-Host "Final Parameter Values:" -ForegroundColor DarkCyan
    Write-Host "  directory:         $directory"
    Write-Host "  ref:               $ref"
    Write-Host "  address:           $address"
    Write-Host "  remote:            $remote"
    Write-Host "  addressSecondary:  $addressSecondary"
    Write-Host "  remoteSecondary:   $remoteSecondary"
    Write-Host "  addressTertiary:   $addressTertiary"
    Write-Host "  remoteTertiary:    $remoteTertiary"
    Write-Host "  throwOnErrors:     $throwOnErrors"
    Write-Host "  defaultFromVars:   $defaultFromVars"
    Write-Host ""

    # Validate that we have either an existing repo or an address
    if (-not $address -and $directory) {
        if (-not (Test-Path $directory)) {
            Write-ErrorReport "Directory ${directory} does not exist, and no address specified to clone from." -throwOnErrors:$throwOnErrors
            return
        } else {
            if (-not (IsGitRepository $directory)) {
                Write-ErrorReport "Directory ${directory} is not a valid Git repository, and no address was specified." -throwOnErrors:$throwOnErrors
                return
            }
        }
    }

    # If directory doesn't exist, create it so we can clone
    if ($directory -and -not (Test-Path $directory)) {
        try {
            New-Item -ItemType Directory -Path $directory | Out-Null
            Write-Info "Created directory: $directory"
        }
        catch {
            Write-ErrorReport "Could not create directory: ${directory}" -throwOnErrors:$throwOnErrors
            return
        }
    }

    # If directory exists and is non-empty, ensure correct repository
    $dirExists = (Test-Path $directory -PathType Container)
    if ($dirExists) {
        $items = Get-ChildItem -Path $directory
        $isEmpty = ($items | Measure-Object).Count -eq 0
        if (-not $isEmpty) {
            if (-not (IsGitRepository $directory)) {
                Write-ErrorReport "Repository directory (${directory}) is not empty and does not contain a valid Git repo." -throwOnErrors:$throwOnErrors
                return
            } else {
                # Check remote consistency if $address is set
                if ($address) {
                    $existingRemote = GetGitRemoteAddress $directory $remote
                    if ($existingRemote) {
                        $consistent = CheckGitAddressConsistency $address $existingRemote
                        if (-not $consistent) {
                            Write-ErrorReport "Repository directory (${directory}) has remote '$remote' set to '$existingRemote' but should be '$address'." -throwOnErrors:$throwOnErrors
                            return
                        }
                    }
                }
            }
        }
    }

    # Clone if needed
    if ($address -and (!$dirExists -or ($dirExists -and $isEmpty))) {
        try {
            Write-Info "Cloning repository from $address into $directory..."
            git clone --origin $remote $address $directory
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorReport "Failed to clone repository from $address into ${directory}." -throwOnErrors:$throwOnErrors
                return
            }
        }
        catch {
            Write-ErrorReport ("Exception occurred while cloning from ${address} into ${directory}: " + $_) -throwOnErrors:$throwOnErrors
            return
        }
    } else {
        # If we already have the repository, fetch from the primary remote
        if ($address) {
            Write-Info "Fetching changes from remote '$remote'..."
            try {
                git -C $directory fetch $remote
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to fetch updates in ${directory}." -throwOnErrors:$throwOnErrors
                    return
                }
            }
            catch {
                Write-ErrorReport ("Exception occurred while fetching in ${directory}: " + $_) -throwOnErrors:$throwOnErrors
                return
            }
        }
    }

    # Handle secondary remote
    if ($addressSecondary) {
        Write-Info "Ensuring secondary remote ($remoteSecondary) points to $addressSecondary"
        try {
            git -C $directory remote add $remoteSecondary $addressSecondary 2>$null
            if ($LASTEXITCODE -ne 0) {
                # If add fails, try set-url
                git -C $directory remote set-url $remoteSecondary $addressSecondary
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Could not set secondary remote '$remoteSecondary' to '$addressSecondary'."
                } else {
                    Write-Warn "Changed address of existing remote '$remoteSecondary' to '$addressSecondary'"
                }
            } else {
                Write-Info "Remote '$remoteSecondary' set to '$addressSecondary'"
            }
        }
        catch {
            Write-ErrorReport ("Exception occurred while setting secondary remote: " + $_) -throwOnErrors:$throwOnErrors
            return
        }
    }

    # Handle tertiary remote
    if ($addressTertiary) {
        Write-Info "Ensuring tertiary remote ($remoteTertiary) points to $addressTertiary"
        try {
            git -C $directory remote add $remoteTertiary $addressTertiary 2>$null
            if ($LASTEXITCODE -ne 0) {
                # If add fails, try set-url
                git -C $directory remote set-url $remoteTertiary $addressTertiary
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Could not set tertiary remote '$remoteTertiary' to '$addressTertiary'."
                } else {
                    Write-Warn "Changed address of existing remote '$remoteTertiary' to '$addressTertiary'"
                }
            } else {
                Write-Info "Remote '$remoteTertiary' set to '$addressTertiary'"
            }
        }
        catch {
            Write-ErrorReport ("Exception occurred while setting tertiary remote: " + $_) -throwOnErrors:$throwOnErrors
            return
        }
    }

    # Check out ref if specified
    if ($ref) {
        Write-Info "Ensuring repository is checked out at reference '$ref'"
        try {
            git -C $directory checkout $ref 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Info "Local branch/ref '$ref' not found, attempting to fetch and create local branch."
                git -C $directory fetch $remote
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to fetch from remote '$remote'." -throwOnErrors:$throwOnErrors
                    return
                }
                git -C $directory checkout -b $ref "$remote/$ref"
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to check out new branch '$ref' from remote '$remote'." -throwOnErrors:$throwOnErrors
                    return
                }
                Write-Warn "Current branch changed to '$ref' (new local branch tracking '$remote/$ref')."
            } else {
                Write-Warn "Repository switched to '$ref' (could be branch, tag, or commit)."
            }
        }
        catch {
            Write-ErrorReport ("Failed to checkout reference '$ref': " + $_) -throwOnErrors:$throwOnErrors
            return
        }
        # If it's a branch, we can pull to update
        $currentBranch = (git -C $directory branch --show-current 2>$null).Trim()
        if ($currentBranch -eq $ref) {
            Write-Info "Pulling latest commits for branch '$ref' from '$remote'"
            try {
                git -C $directory pull $remote $ref
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to pull latest changes for branch '$ref'." -throwOnErrors:$throwOnErrors
                    return
                }
            }
            catch {
                Write-ErrorReport ("Exception occurred while pulling latest changes for branch '$ref': " + $_) -throwOnErrors:$throwOnErrors
                return
            }
            Write-Info "Repository in '${directory}' is now updated to the latest commit of branch '$ref'"
        }
        else {
            # Possibly a detached HEAD if ref is a tag or commit
            Write-Info "The repository in '${directory}' is checked out at '$ref' (possibly a detached HEAD)."
            Write-Info "Fetching from remote '$remote' in case the tag or commit was updated..."
            try {
                git -C $directory fetch $remote --tags
            }
            catch {
                Write-Warn ("Could not fetch from remote '$remote' for tag or commit: " + $_)
            }
        }
    }
    else {
        Write-Info "No ref specified. Repository remains on its current branch/tag/commit."
    }

    Write-Info "Repository is up to date in directory: ${directory}"
}

###############################################################################
# Script-level Parameter Resolution & Execution Control
###############################################################################

function Resolve-ScriptParameters {
    # 1) Fill from global variables if $DefaultFromVars is set, then apply defaults, etc.
    if ($DefaultFromVars) {
        Write-Info "Resolve-ScriptParameters called with DefaultFromVars = $DefaultFromVars. Attempting to fill script parameters from global variables..."

        # Use PascalCase param names to match main function logic
        $paramList = 'Directory','Ref','Address','Remote','AddressSecondary','RemoteSecondary','AddressTertiary','RemoteTertiary'
        foreach ($p in $paramList) {
            $scriptParamValue = (Get-Variable -Name $p -Scope 1 -ErrorAction SilentlyContinue).Value
            if ($scriptParamValue) {
                Write-Info "  $p is already set in script parameters to: $scriptParamValue"
            }
            else {
                # Build the global var name, e.g. "RepositoryDirectory"
                $upperParam  = $p.Substring(0,1).ToUpper() + $p.Substring(1)
                $globalVarName = "${ParameterGlobalVariablePrefix}${upperParam}"

                Write-Info "  Checking global variable name: $globalVarName"
                $globalVal = (Get-Variable -Name $globalVarName -Scope Global -ErrorAction SilentlyContinue).Value
                Write-Info "  >> Global variable value: $globalVal"

                if ($globalVal) {
                    Set-Variable -Name $p -Value $globalVal -Scope 1
                    Write-Info "  $p set from $globalVarName to $globalVal"
                }
                else {
                    Write-Info "  $p not set from global variable."
                }
            }
        }
    }

    # 2) Apply default values if not set
    if (-not $Remote)          { $Remote          = $DefaultRemote }
    if (-not $RemoteSecondary) { $RemoteSecondary = $DefaultRemoteSecondary }
    if (-not $RemoteTertiary)  { $RemoteTertiary  = $DefaultRemoteTertiary }
}

function Set-GlobalVarsIfRequested {
    if ($ParamsToVars) {
        $paramList = 'Directory','Ref','Address','Remote','AddressSecondary','RemoteSecondary','AddressTertiary','RemoteTertiary'
        foreach ($p in $paramList) {
            $value = (Get-Variable -Name $p -Scope 1 -ErrorAction SilentlyContinue).Value
            if ($null -ne $value) {
                $upperParam  = $p.Substring(0,1).ToUpper() + $p.Substring(1)
                $globalVarName = "${ParameterGlobalVariablePrefix}${upperParam}"

                Set-Variable -Name $globalVarName -Value $value -Scope Global
                Write-Info "Set global variable $globalVarName to $value"
            }
        }
    }
}

Resolve-ScriptParameters

# Decide whether to call the main function based on the logic described:
# 1) If $Execute is true, run the main function unconditionally.
# 2) If $Execute is false, do NOT run the main function.
# 3) If $Execute is not specified, but Address or Directory are specified, run the main function.

$shouldExecute = $false
if ($Execute.IsPresent) {
    if ($Execute) {
        $shouldExecute = $true
    } else {
        $shouldExecute = $false
    }
}
else {
    if ($PSBoundParameters.ContainsKey('Address') -or $PSBoundParameters.ContainsKey('Directory')) {
        $shouldExecute = $true
    }
}

Set-GlobalVarsIfRequested

if ($shouldExecute) {
    UpdateOrCloneRepository `
        -directory $Directory `
        -ref $Ref `
        -address $Address `
        -remote $Remote `
        -addressSecondary $AddressSecondary `
        -remoteSecondary $RemoteSecondary `
        -addressTertiary $AddressTertiary `
        -remoteTertiary $RemoteTertiary `
        -throwOnErrors:$ThrowOnErrors `
        -defaultFromVars:$DefaultFromVars
}
