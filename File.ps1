#!/usr/bin/env pwsh

# Helper utilities for dealing with file paths and other file system related tasks
# https://github.com/ajgorhoe/IGLib.modules.IGLibScriptsPS.git

# Execute definitions from other files:
. "$(Join-Path "$PSScriptRoot" "Common.ps1")"

# Check whether the current script has already been executed before:
CheckScriptExecuted $ExecutedScriptPath_File $MyInvocation.MyCommand.Path;
# Store scritp path in a variable in order to enable later verifications:
$ExecutedScriptPath_File = $MyInvocation.MyCommand.Path

# Auxiliary definitions:
Set-Alias print Write-Host
Set-Alias alias Set-Alias
Set-Alias aliases Get-Alias
Set-Alias ScripttDir GetScriptDirectory
Set-Alias CurrentDir GetCurrentDirectory
Set-Alias FullPath GetAbsolutePath
Set-Alias IsFile FileExists
Set-Alias DirExists DirectoryExists
Set-Alias IsDir DirectoryExists
Set-Alias AbsolutePath GetAbsolutePath
Set-Alias FileName GetFileName
Set-Alias GetFileOrDirectoryName GetFileName
Set-Alias ParentDir GetParentDirectory
Set-Alias RootDir GetRootDirectory
Set-Alias CopyDir CopyDirectoryRecursive
Set-Alias RemoveDir RemoveDirectoryRecursive
Set-Alias Files GetFilesRecursively
Set-Alias FilesRun RunOnFilesRecursively
Set-Alias OnFiles RunOnFilesRecursively

function GetScriptDirectoryIGLib() { $PSScriptRoot }

function GetScriptDirectory()
{ $MyInvocation.MyCommand.Path }

function GetCurrentDirectory() { return $(Get-Location).Path }

function DirectoryExists(<#[system.string]#> $DirectoryPath = $null)
{
	if ("$DirectoryPath" -eq "") { return $false; }
	return Test-Path "$DirectoryPath" -PathType Container
}

function FileExists(<#[system.string]#>  $FilePath = $null)
{
	if ("$FilePath" -eq "") { return $false; }
	return Test-Path "$FilePath" -PathType Leaf
}

function PathExists($Path = $null)
{
	if ("$Path" -eq "") { return $false; }
	return Test-Path "$Path"
}

function GetAbsolutePath($Path = $null)
{
	if ("$Path" -eq "") { $Path = "."; }
	return $(Resolve-Path "$Path").Path;
}

<#
.Synopsis
Returns the filaname part of the specific file path.
.Description
Returns the filaname part of the specific file path. This function does not 
check whether the $Path parameter actually contains a path of an existing 
file, and operates merely on path-as-string basis. For example, if $Path
is a path of an existing directory, then this function will just return the
name of the last level of the directory.
.Parameter Path
Specifies the file name.
#>
function GetFileName($Path = ".")
{
	if ("$Path" -eq "") { $Path = "." }
	if (PathExists($Path))
	{
		$Path = GetAbsolutePath($Path);
	}
	return Split-Path "$Path" -Leaf
}

function GetParentDirectory($Path = ".")
{
	if ("$Path" -eq "") { $Path = "." }
	if (PathExists($Path))
	{
		return Split-Path "$Path" -Resolve
	}
	return Split-Path "$Path"
}

function GetRootDirectory($Path = $null, $ChildPath = $null)
{
#	print GetRootDirectory called with:
#	print "  Path: $Path"
#	print "  ChildPath: $ChildPath"
	if ("$Path" -eq "" -and "$ChildPath" -eq "") { $Path = "."; }
	if ($(PathExists("$Path")) -or $true)
	{
		$ParentPath = GetParentDirectory($Path);
#		print "Path: $Path"
#		print "ParentPath: $ParentPath"
		if ("$ParentPath" -eq "")  {
			return $Path; 
		}
#		print "Calling: GetRootDirectory($ParentPath, $Path)";
		return GetRootDirectory $ParentPath $Path
	} else
	{
		return $null;
	}
}

# Recursively copies the directory at $Path to the $Destination.
function CopyDirectoryRecursive($DirectoryPath, $DestinationPath)
{
	Copy-Item "$DirectoryPath" -Destination "$DestinationPath" -Recurse
}

# Recursively removes the specified directory.
function RemoveDirectoryRecursive($DirectoryPath)
{
	Remove-Item -Recurse -Force "$DirectoryPath"
}

# Returns all files contained in the spexified directories
function GetFilesRecursively($DirectoryPath, $Filter = $null, 
	$IncludeFiles = $true, $IncludeDirectories = $true)
{
	if (-not $(DirectoryExists $DirectoryPath))
	{
		return $null;
	}
	return Get-ChildItem "$DirectoryPath" -Filter "$Filter" -Recurse | ForEach-Object { $_.FullName }
	# return Get-ChildItem "$DirectoryPath" -Filter "$Filter" -Recurse | % { $_.FullName }
}

function RunOnFilesRecursively($DirectoryPath, $Filter = $null, 
	$IncludeFiles = $true, $IncludeDirectories = $true, $Function)
{
	foreach ($file in $(GetFilesRecursively($DirectoryPath, $Filter, $IncludeFiles, $IncludeDirectories)))
	{
		Write-Host "Executing on file: $(FileName $File)..."
		$result_75937548 = . $function $file
		Write-Host "Result of function evaluation: $result_75937548"
	}
}

function ExamplesRunOnFilesRecursive()
{
	# Calculation of total size of filtered files contained in a directory (recursive) - manual using Files:
	# Remark - in PowerShell, $($null + 1) evaluates to 1. 
	# Remark: running with trailing '.' will pass variable values to the calling context.
	. Files "." "*.ps1" | ForEach-Object {   # Could also use %
		$f=$_;  
		if ($(IsFile $f)) {
			$TotalLength = $TotalLength +  $(Get-Item  $f).Length;
		}
	}
	Write-Host "`nTotal size of all .ps1 files included in the current directory: $TotalLength"
	# The same calculation using OnFiles (=RunOnFilesRecursively), with script block (anonumous function):
	# Reset the total size:
	$TotalLength = 0
	. OnFiles "." "*.ps1" -Function { 
		param ($filePath) # Define function parameter list within the block, like in scripts
		if ($(IsFile $filePath)) {
			$TotalLength = $TotalLength +  $(Get-Item  $filePath).Length;
			Write-Host "Accummulated value: TotalLength = $TotalLength ."
		}
	}
	Write-Host "`nTotal size via OnFiles, using anonymous function: $TotalLength"
	# Via defined function:
	function AddFileLength ($filePath) {
		if ($(IsFile $filePath)) {
			$TotalLength = $TotalLength +  $(Get-Item  $filePath).Length;
			Write-Host "Accummulated value: TotalLength = $TotalLength ."
		}
	}
	. OnFiles "." "*.ps1" -Function AddFileLength
	Write-Host "`nTotal size via OnFiles, using named function AddFileLength(): $TotalLength"
}


ExamplesRunOnFilesRecursive








