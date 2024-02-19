#!/usr/bin/env pwsh

# Helper utilities for dealing with reopsitories
# https://github.com/ajgorhoe/IGLib.modules.IGLibScriptsPS.git

# Execute definitions from other files:
. $(Join-Path "$PSScriptRoot" "File.ps1")

# Check whether the current script has already been executed before:
CheckScriptExecuted $ExecutedScriptPath_GitHelpers $MyInvocation.MyCommand.Path;
# Store scritp path in a variable in order to enable later verifications:
$ExecutedScriptPath_GitHelpers = $MyInvocation.MyCommand.Path

Set-Alias GitRoot GetGitRoot
Set-Alias GitBranch GetGitBranch
Set-Alias GitCommit GetGitCommit
Set-Alias ShortGitCommit GetShortGitCommit
Set-Alias GitShortCommit GetShortGitCommit
Set-Alias SetBranch SetGitBranch 


function IsGitRoot($DirectoryPath = ".")
{
	if ("$DirectoryPath" -eq "") { $DirectoryPath = "." }
	$GitRefDirectoryName = ".git/refs"
	$GitRefDirectoryPath = $(Join-Path "$DirectoryPath" `
		"$GitRefDirectoryName")
	return Test-Path "$GitRefDirectoryPath" -PathType Container
}


function IsGitWorkingDirectory($DirectoryPath = ".")
{
	if ("$DirectoryPath" -eq "") { $DirectoryPath = "." }
	if (IsGitRoot($DirectoryPath)) { return $true; }
	$ParentDir = ParentDir "$DirectoryPath"
	if ("$ParentDir" -eq "") { return $false }
	return IsGitWorkingDirectory "$ParentDir"
}

function GetGitRoot($DirectoryPath = ".")
{
	if ("$DirectoryPath" -eq "") { $DirectoryPath = "." }
	if (IsGitRoot($DirectoryPath)) { 
		return (Resolve-Path $DirectoryPath).Path; }
	$ParentDir = ParentDir "$DirectoryPath"
	if ("$ParentDir" -eq "") 
	{
		Write-Host "`GetGitRoot(): not a Git working directory.`n"
		return $null 
	}
	return GetGitRoot "$ParentDir"
}

function GetGitBranch($DirectoryPath = ".")
{
	if ("$DirectoryPath" -eq "") { $DirectoryPath = "." }
	if (-not (IsGitWorkingDirectory "$DirectoryPath"))
	{
		Write-Host "`nGetGitBranch(): not a Git working directory.`n"
		return $null
	}
	$InitialDir = $(Get-Location).Path
	$ret = $null
	try {
		if ("$DirectoryPath" -ne "") { Set-Location "$DirectoryPath" }  # { cd ... }
		$ret = $(git rev-parse --abbrev-ref HEAD)
	}
	catch {
		Write-Host "ERROR in GetGitBranch(): $($_.Exception.Message)`n"
	}
	finally {
		Set-Location "$InitialDir"  # cd ...
	}
	return $ret
}


function GetGitCommit($DirectoryPath = ".", $ShortLength)
{
	if ("$DirectoryPath" -eq "") { $DirectoryPath = "." }
	if (-not (IsGitWorkingDirectory "$DirectoryPath"))
	{
		Write-Host "`nGetGitCommit(): not a Git working directory.`n"
		return $null
	}
	$InitialDir = $(Get-Location).Path
	$ret = $null
	try {
		if ("$DirectoryPath" -ne "") { cd "$DirectoryPath" }
		$ret = $(git rev-parse HEAD)
		if ("$ShortLength" -ne "")
		{
			$ret = $ret[0..$ShortLength] -join''
		}
	}
	catch {
		Write-Host "`nERROR in GetGitCommit(): $($_.Exception.Message)`n"
	}
	finally {
		Set-Location "$InitialDir"  # cd ...
	}
	return $ret
}

function GetShortGitCommit($DirectoryPath = ".")
{
return GetGitCommit $DirectoryPath 4;
}

function SetGitBranch($BranchCommitOrTag, $DirectoryPath = ".")
{
	if ("$BranchCommitOrTag" -eq "") {
		Write-Host "`nSetGitBranch(): Branch, commit or tag not specified.`n"
		return
	}
	if ("$DirectoryPath" -eq "") { $DirectoryPath = "." }
	if (-not (IsGitWorkingDirectory "$DirectoryPath"))
	{
		Write-Host "`nGetGitBranch(): not a Git working directory.`n"
		return $null
	}
	$InitialDir = $(Get-Location).Path
	$ret = $null
	try {
		if ("$DirectoryPath" -ne "") { Set-Location "$DirectoryPath" }  # { cd ... }
		# $(git rev-parse --abbrev-ref HEAD)
		$(git checkout "$BranchCommitOrTag")
	}
	catch {
		Write-Host "ERROR in GetGitBranch(): $($_.Exception.Message)`n"
	}
	finally {
		Set-Location "$InitialDir"  # cd ...
	}
	return $ret
}


function GitClone ($RepositoryAddress = $null, 
	$CloneDirectory = $null, $BranchCommitOrTag = $null )
{
	if ("$RepositoryAddress" -eq "")
	{
		Write-Host "Error: GitClone(): RepositoryAddress not specified"
		return;
	}
	if ("$CloneDirectory" -ne "")
	{
		if (IsGitWorkingDirectory "$CloneDirectory")
		{
			Write-Host "`nGitClone(): Directory already contains a Git repository: $CloneDirectory`n"
			return null;
		}
	}
	if ("$BranchCommitOrTag" -ne "")
	{
		. git clone "$RepositoryAddress" "$CloneDirectory" --branch "$BranchCommitOrTag"
	} else {
		. git clone "$RepositoryAddress" "$CloneDirectory"
	}
}

function GitUpdate ($CloneDirectory = ".", $BranchCommitOrTag = $null )
{
	$InitialDir = $(Get-Location).Path  # (pwd).Path
	# $ret = $null
	if ("$CloneDirectory" -eq "") { $CloneDirectory = "." }
	if (-not (IsGitWorkingDirectory "$CloneDirectory"))
	{
		Write-Host "`nError: GitUpdate(): Not a Git working directory: $CloneDirectory`n"
		return
	}
	try 
	{
		Set-Location "$CloneDirectory"  # cd ...
		if ("$BranchCommitOrTag" -eq "")
		{
			# branch not specified
			. git pull
			return 
		}
		try
		{
			. git fetch --all --tags
			. git checkout "$BranchCommitOrTag"
			. git pull
		}
		catch {   }
		return 
	}
	finally { Set-Location "$InitialDir"  }  # cd ...
}

function GitCloneOrUpdate($RepositoryAddress = $null, 
	$CloneDirectory = $null, $BranchCommitOrTag = $null )
{
	if ("$CloneDirectory" -eq "") { $CloneDirectory = "." }
	if ("$RepositoryAddres" -ne "")
	{
		GitClone "$RepositoryAddres" "$CloneDirectory" "$BranchCommitOrTag"
	}
}

function GitCloneOrUpdate($RepositoryAddress = $null,
	$BranchTagOrCommit=$null)
# Returns a set of parts of the string version of form "1.2.3.4"
{
	if ($null -eq $versionString -or $versionString -eq "") 
	{ $versionString = "1.0.0.0" }
	return $versionString.Replace(".",",").Split(",")
}



