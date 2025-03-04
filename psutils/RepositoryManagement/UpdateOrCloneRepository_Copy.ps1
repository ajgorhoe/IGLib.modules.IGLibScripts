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
    [switch]$ParamsToVars,
    [string]$BaseDirectory
)

###############################################################################
# Constants & Defaults
###############################################################################

# Prefix used for setting/retrieving global variables
$ParameterGlobalVariablePrefix = "CurrentRepo_"

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
    param (
        [string]$Path,
        [string]$BaseDirectory
    )
    # If the path is already absolute, we just try to resolve.
    if ([IO.Path]::IsPathRooted($Path)) {
        try {
            return (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
        } catch {
            return $Path  # Return raw path if it doesn't exist
        }
    }
    else {
        # The path is relative. If BaseDirectory is specified & valid, we use that.
        if ($BaseDirectory) {
            try {
                if (Test-Path $BaseDirectory -PathType Container) {
                    $combinedPath = Join-Path $BaseDirectory $Path
                    # Try to resolve:
                    return (Resolve-Path -LiteralPath $combinedPath -ErrorAction Stop).Path
                }
                else {
                    # If BaseDirectory does not exist, we just combine as raw path
                    return Join-Path $BaseDirectory $Path
                }
            } catch {
                return Join-Path $BaseDirectory $Path
            }
        }
        else {
            # Fall back to old logic: combine with script directory or current dir
            if ($MyInvocation.MyCommand.Path) {
                $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
                $combinedPath = Join-Path $scriptDir $Path
            } else {
                $combinedPath = Join-Path (Get-Location) $Path
            }
            try {
                return (Resolve-Path -LiteralPath $combinedPath -ErrorAction Stop).Path
            } catch {
                return $combinedPath
            }
        }
    }
}

###############################################################################
# Main Function
###############################################################################

function UpdateOrCloneRepository {
    param (
        [string]$Directory,
        [string]$Ref,
        [string]$Address,
        [string]$Remote = $DefaultRemote,
        [string]$AddressSecondary,
        [string]$RemoteSecondary = $DefaultRemoteSecondary,
        [string]$AddressTertiary,
        [string]$RemoteTertiary = $DefaultRemoteTertiary,
        [switch]$ThrowOnErrors,
        [switch]$DefaultFromVars,
        [string]$BaseDirectory
    )

    Write-Info "Updating or cloning a repository..."

    ############################################################################
    # (1) If $DefaultFromVars, fill any missing parameters from global variables
    ############################################################################
    if ($DefaultFromVars) {
        Write-Info "DefaultFromVars is set (function scope). Checking for missing parameters..."

        $paramList = 'Directory','Ref','Address','Remote','AddressSecondary','RemoteSecondary','AddressTertiary','RemoteTertiary','BaseDirectory'
        foreach ($p in $paramList) {
            # Did the caller explicitly specify this parameter?
            if (-not $PSBoundParameters.ContainsKey($p)) {
                # The user did NOT pass this parameter, so let's try to fill from global
                $upperParam   = $p.Substring(0,1).ToUpper() + $p.Substring(1)
                $globalVarName = "${ParameterGlobalVariablePrefix}${upperParam}"

                $currentVal = Get-Variable -Name $p -Scope 0 -ErrorAction SilentlyContinue

                # We must check .Value to see if the param is actually set
                if ($currentVal -and $currentVal.Value) {
                    Write-Info "  $p is already set (somehow). No override from global. Value: $($currentVal.Value)"
                    continue
                }

                Write-Info "  Checking global variable: $globalVarName"
                $globalVal = (Get-Variable -Name $globalVarName -Scope Global -ErrorAction SilentlyContinue).Value
                Write-Info "  >> Global variable value: $globalVal"

                if ($globalVal) {
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
    if (-not $Remote)           { $Remote           = $DefaultRemote }
    if (-not $RemoteSecondary)  { $RemoteSecondary  = $DefaultRemoteSecondary }
    if (-not $RemoteTertiary)   { $RemoteTertiary   = $DefaultRemoteTertiary }

    ############################################################################
    # (3) Additional logic for deduce Directory from Address (if needed)
    ############################################################################
    # But if Directory is relative and BaseDirectory is specified, we do that logic in EnsureFullPath.
    if (-not $Directory -and $Address) {
        $repoName = GetGitRepositoryName $Address
        if ($repoName) {
            $Directory = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) $repoName
        } else {
            $Directory = Join-Path (Split-Path $MyInvocation.MyCommand.Path -Parent) "Repo"
        }
    }

    # Convert to full path (honoring BaseDirectory if set)
    if ($Directory) {
        $Directory = EnsureFullPath -Path $Directory -BaseDirectory $BaseDirectory
    }

    # If Directory is specified but Address is not, try to deduce from existing remote
    if (-not $Address -and $Directory) {
        if (Test-Path $Directory -PathType Container -and (IsGitRepository $Directory)) {
            $existingAddr = GetGitRemoteAddress $Directory $Remote
            if ($existingAddr) {
                $Address = $existingAddr
                Write-Info "Deduced address from existing remote '$Remote': $Address"
            }
        }
    }

    ############################################################################
    # (4) Print final parameter values (after resolution), then validate
    ############################################################################
    Write-Host "Final Parameter Values:" -ForegroundColor DarkCyan
    Write-Host "  Directory:         $Directory"
    Write-Host "  Ref:               $Ref"
    Write-Host "  Address:           $Address"
    Write-Host "  Remote:            $Remote"
    Write-Host "  AddressSecondary:  $AddressSecondary"
    Write-Host "  RemoteSecondary:   $RemoteSecondary"
    Write-Host "  AddressTertiary:   $AddressTertiary"
    Write-Host "  RemoteTertiary:    $RemoteTertiary"
    Write-Host "  ThrowOnErrors:     $ThrowOnErrors"
    Write-Host "  DefaultFromVars:   $DefaultFromVars"
    Write-Host "  BaseDirectory:     $BaseDirectory"
    Write-Host ""

    # Validate that we have either an existing repo or an Address
    if (-not $Address -and $Directory) {
        if (-not (Test-Path $Directory)) {
            Write-ErrorReport "Directory ${Directory} does not exist, and no Address specified to clone from." -throwOnErrors:$ThrowOnErrors
            return
        } else {
            if (-not (IsGitRepository $Directory)) {
                Write-ErrorReport "Directory ${Directory} is not a valid Git repository, and no Address was specified." -throwOnErrors:$ThrowOnErrors
                return
            }
        }
    }

    # If Directory doesn't exist, create it so we can clone
    $dirExists = $false
    if ($Directory) {
        $dirExists = Test-Path $Directory -PathType Container
        if (-not $dirExists) {
            try {
                New-Item -ItemType Directory -Path $Directory | Out-Null
                Write-Info "Created directory: $Directory"
                $dirExists = $true
            }
            catch {
                Write-ErrorReport "Could not create directory: ${Directory}" -throwOnErrors:$ThrowOnErrors
                return
            }
        }
    }

    # If directory exists and is non-empty, ensure correct repository
    if ($dirExists) {
        $items = Get-ChildItem -Path $Directory
        $isEmpty = ($items | Measure-Object).Count -eq 0
        if (-not $isEmpty) {
            if (-not (IsGitRepository $Directory)) {
                Write-ErrorReport "Repository directory (${Directory}) is not empty and does not contain a valid Git repo." -throwOnErrors:$ThrowOnErrors
                return
            } else {
                # Check remote consistency if $Address is set
                if ($Address) {
                    $existingRemote = GetGitRemoteAddress $Directory $Remote
                    if ($existingRemote) {
                        $consistent = CheckGitAddressConsistency $Address $existingRemote
                        if (-not $consistent) {
                            Write-ErrorReport "Repository directory (${Directory}) has remote '$Remote' set to '$existingRemote' but should be '$Address'." -throwOnErrors:$ThrowOnErrors
                            return
                        }
                    }
                }
            }
        }
    }

    # Clone if needed
    if ($Address -and (!$dirExists -or ($dirExists -and $isEmpty))) {
        try {
            Write-Info "Cloning repository from $Address into $Directory..."
            git clone --origin $Remote $Address $Directory
            if ($LASTEXITCODE -ne 0) {
                Write-ErrorReport "Failed to clone repository from $Address into ${Directory}." -throwOnErrors:$ThrowOnErrors
                return
            }
        }
        catch {
            Write-ErrorReport ("Exception occurred while cloning from ${Address} into ${Directory}: " + $_) -throwOnErrors:$ThrowOnErrors
            return
        }
    } else {
        # If we already have the repository, fetch from the primary remote
        if ($Address) {
            Write-Info "Fetching changes from remote '$Remote'..."
            try {
                git -C $Directory fetch $Remote
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to fetch updates in ${Directory}." -throwOnErrors:$ThrowOnErrors
                    return
                }
            }
            catch {
                Write-ErrorReport ("Exception occurred while fetching in ${Directory}: " + $_) -throwOnErrors:$ThrowOnErrors
                return
            }
        }
    }

    # Handle secondary remote
    if ($AddressSecondary) {
        Write-Info "Ensuring secondary remote ($RemoteSecondary) points to $AddressSecondary"
        try {
            git -C $Directory remote add $RemoteSecondary $AddressSecondary 2>$null
            if ($LASTEXITCODE -ne 0) {
                # If add fails, try set-url
                git -C $Directory remote set-url $RemoteSecondary $AddressSecondary
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Could not set secondary remote '$RemoteSecondary' to '$AddressSecondary'."
                } else {
                    Write-Warn "Changed address of existing remote '$RemoteSecondary' to '$AddressSecondary'"
                }
            } else {
                Write-Info "Remote '$RemoteSecondary' set to '$AddressSecondary'"
            }
        }
        catch {
            Write-ErrorReport ("Exception occurred while setting secondary remote: " + $_) -throwOnErrors:$ThrowOnErrors
            return
        }
    }

    # Handle tertiary remote
    if ($AddressTertiary) {
        Write-Info "Ensuring tertiary remote ($RemoteTertiary) points to $AddressTertiary"
        try {
            git -C $Directory remote add $RemoteTertiary $AddressTertiary 2>$null
            if ($LASTEXITCODE -ne 0) {
                # If add fails, try set-url
                git -C $Directory remote set-url $RemoteTertiary $AddressTertiary
                if ($LASTEXITCODE -ne 0) {
                    Write-Warn "Could not set tertiary remote '$RemoteTertiary' to '$AddressTertiary'."
                } else {
                    Write-Warn "Changed address of existing remote '$RemoteTertiary' to '$AddressTertiary'"
                }
            } else {
                Write-Info "Remote '$RemoteTertiary' set to '$AddressTertiary'"
            }
        }
        catch {
            Write-ErrorReport ("Exception occurred while setting tertiary remote: " + $_) -throwOnErrors:$ThrowOnErrors
            return
        }
    }

    # Check out Ref if specified
    if ($Ref) {
        Write-Info "Ensuring repository is checked out at reference '$Ref'"
        try {
            git -C $Directory checkout $Ref 2>$null
            if ($LASTEXITCODE -ne 0) {
                Write-Info "Local branch/ref '$Ref' not found, attempting to fetch and create local branch."
                git -C $Directory fetch $Remote
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to fetch from remote '$Remote'." -throwOnErrors:$ThrowOnErrors
                    return
                }
                git -C $Directory checkout -b $Ref "$Remote/$Ref"
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to check out new branch '$Ref' from remote '$Remote'." -throwOnErrors:$ThrowOnErrors
                    return
                }
                Write-Warn "Current branch changed to '$Ref' (new local branch tracking '$Remote/$Ref')."
            } else {
                Write-Warn "Repository switched to '$Ref' (could be branch, tag, or commit)."
            }
        }
        catch {
            Write-ErrorReport ("Failed to checkout reference '$Ref': " + $_) -throwOnErrors:$ThrowOnErrors
            return
        }
        # If it's a branch, we can pull to update
        $currentBranch = (git -C $Directory branch --show-current 2>$null).Trim()
        if ($currentBranch -eq $Ref) {
            Write-Info "Pulling latest commits for branch '$Ref' from '$Remote'"
            try {
                git -C $Directory pull $Remote $Ref
                if ($LASTEXITCODE -ne 0) {
                    Write-ErrorReport "Failed to pull latest changes for branch '$Ref'." -throwOnErrors:$ThrowOnErrors
                    return
                }
            }
            catch {
                Write-ErrorReport ("Exception occurred while pulling latest changes for branch '$Ref': " + $_) -throwOnErrors:$ThrowOnErrors
                return
            }
            Write-Info "Repository in '${Directory}' is now updated to the latest commit of branch '$Ref'"
        }
        else {
            # Possibly a detached HEAD if Ref is a tag or commit
            Write-Info "The repository in '${Directory}' is checked out at '$Ref' (possibly a detached HEAD)."
            Write-Info "Fetching from remote '$Remote' in case the tag or commit was updated..."
            try {
                git -C $Directory fetch $Remote --tags
            }
            catch {
                Write-Warn ("Could not fetch from remote '$Remote' for tag or commit: " + $_)
            }
        }
    }
    else {
        Write-Info "No Ref specified. Repository remains on its current branch/tag/commit."
    }

    Write-Info "Repository is up to date in directory: ${Directory}"
}

###############################################################################
# Script-level Parameter Resolution & Execution Control
###############################################################################

function Resolve-ScriptParameters {
    # 1) Fill from global variables if $DefaultFromVars is set, then apply defaults, etc.
    if ($DefaultFromVars) {
        Write-Info "Resolve-ScriptParameters called with DefaultFromVars = $DefaultFromVars. Attempting to fill script parameters from global variables..."

        $paramList = 'Directory','Ref','Address','Remote','AddressSecondary','RemoteSecondary','AddressTertiary','RemoteTertiary','BaseDirectory'
        foreach ($p in $paramList) {
            $scriptParamValue = (Get-Variable -Name $p -Scope 1 -ErrorAction SilentlyContinue).Value
            if ($scriptParamValue) {
                Write-Info "  $p is already set in script parameters to: $scriptParamValue"
            }
            else {
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
        $paramList = 'Directory','Ref','Address','Remote','AddressSecondary','RemoteSecondary','AddressTertiary','RemoteTertiary','BaseDirectory'
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
        -Directory $Directory `
        -Ref $Ref `
        -Address $Address `
        -Remote $Remote `
        -AddressSecondary $AddressSecondary `
        -RemoteSecondary $RemoteSecondary `
        -AddressTertiary $AddressTertiary `
        -RemoteTertiary $RemoteTertiary `
        -ThrowOnErrors:$ThrowOnErrors `
        -DefaultFromVars:$DefaultFromVars `
        -BaseDirectory $BaseDirectory
}
