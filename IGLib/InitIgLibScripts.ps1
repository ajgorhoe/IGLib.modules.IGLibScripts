#!/usr/bin/env pwsh

# Initializes the IGLib Scripting utilities.
# If not yet cloned, this script first clones the IGLibScripts repository
# into the directory ../IGLibScripts relative to the current script 
# directory. Then it executes the script ./InitIGLibCustom.ps1 relative
# to the containing directory of the current script, if the file exists.

# https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git
# Part of the Investigative Generic Library (IGLib).

# Start measuring script execution time:
$startTime = Get-Date

function DirectoryExists(<#[system.string]#> $DirectoryPath = $null)
{
	if ("$DirectoryPath" -eq "") { return $false; }
	return Test-Path "$DirectoryPath" -PathType Container
}
function GetAbsolutePath($Path = $null)
{
	if ("$Path" -eq "") { $Path = "."; }
	return $(Resolve-Path "$Path").Path;
}

# Containg directory of the IGLibScripts and other IGLib repos:
$RootDirIGLib = $(GetAbsolutePath $(Join-Path "$PSScriptRoot" "./"))
# Clone directory of IGLibScripts:
$DirIGLibScripts = $(GetAbsolutePath $(Join-Path "$RootDirIGLib" "IGLibScripts"))
# Checked-out branch of IGLibScripts repo (null or "" for default):
$BranchIGLibScripts = $null
# Repository address of IGLibScripts: 
$RepoAddrIGLibScripts = "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"
# Script for loading utility scripts (relative to IGLibScripts clone direcory):
$UtilityScriptLoaderRelative = "ImportAllRoot.ps1"

$RepositoryAddress = $RepoAddrIGLibScripts
$CloneDirectory = $DirIGLibScripts
$CloneMetadataDirectory = $(GetAbsolutePath $(Join-Path "$CloneDirectory" ".git/"))

# Branch to be checked out after cloning:
$BranchCommitOrTag = $BranchIGLibScripts

$middleTime = (Get-Date) - $startTime
Write-Output ""
Write-Output "Execution time after script setup: $($middleTime.TotalSeconds) seconds"
Write-Output ""

Write-Output ""
if ($(DirectoryExists "$CloneMetadataDirectory"))
{
	Write-Output "IGLibScripts repository already cloned."
} else 
{
	# If the IGLIBScripts clone directory does not exist at $DirIGLibScripts
	# then clone it:
	if ("$BranchCommitOrTag" -ne "")
	{
		. git clone "$RepositoryAddress" "$CloneDirectory" --branch "$BranchCommitOrTag"
	} else {
		. git clone "$RepositoryAddress" "$CloneDirectory"
	}
	Write-Output "IGLibScripts clone path:"
}
Write-Output "  clone path: $CloneDirectory"
Write-Output ""

$middleTime = (Get-Date) - $startTime
Write-Output ""
Write-Output "Execution time after repository cloning: $($middleTime.TotalSeconds) seconds"
Write-Output ""

Write-Output "Running utility scripts loader from IGLibScripts ..."
$UtilityScriptLoader = $(GetAbsolutePath $(Join-Path  "$CloneDirectory" $UtilityScriptLoaderRelative))
. "$UtilityScriptLoader"
Write-Output ""
Write-Output "  ... utility scripts loader completed:"
Write-Output "    $UtilityScriptLoader"
Write-Output ""

$middleTime = (Get-Date) - $startTime
Write-Output ""
Write-Output "Execution time after loading utility scripts: $($middleTime.TotalSeconds) seconds"
Write-Output ""


# If branch is specified then make sure to check out the correct branch:
if ("$BranchCommitOrTag" -ne "")
{
	Write-Output ""
	Write-Output "Checkout: $BranchCommitOrTag ..."
	GitSetBranch  "$BranchCommitOrTag" "$CloneDirectory"
	Write-Output "  ... checkout done."
	$middleTime = (Get-Date) - $startTime
	Write-Output ""
	Write-Output "Execution time after updating git repository: $($middleTime.TotalSeconds) seconds"
	Write-Output ""
} else {
	Write-Output ""
	Write-Output "Branch not specified, not switching the branch."
	Write-Output ""
}

Write-Output ""
Write-Output "Updating git repository (pulling from origin) ..."
GitUpdate "$CloneDirectory"

$middleTime = (Get-Date) - $startTime
Write-Output ""
Write-Output "Execution time after updating git repository: $($middleTime.TotalSeconds) seconds"
Write-Output ""

