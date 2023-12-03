#!/usr/bin/env pwsh

# Powershell info and helper utilities
# https://github.com/ajgorhoe/IGLib.modules.IGLibScriptsPS.git

# Remark: make sure you have set the execution policy correctly, e.g. (as admin.):
#   Set-ExecutionPolicy RemoteSigned

# Execute definitions from other files:
. "$(Join-Path "$PSScriptRoot" "Common.ps1")"

# Check whether the current script has already been executed before:
CheckScriptExecuted $ExecutedScriptPath_PowerShellInfo $MyInvocation.MyCommand.Path;
# Store scritp path in a variable in order to enable later verifications:
$ExecutedScriptPath_PowerShellInfo = $MyInvocation.MyCommand.Path



# Auxiliary definitions:
Set-Alias print Write-Host
Set-Alias alias Set-Alias
Set-Alias aliases Get-Alias

function PowerShellInfo()
{
	Write-Host 'Version information ($PSVersionTable):'
	# Write-Host $PSVersionTable
	# $PSVersionTable
	$PSVersionTable | Format-Table -AutoSize
}

function ArrayToString($ArrayVar = $null)
{
	if ("$ArrayVar" -eq "") { 
		Write-Host "`nError in ArrayToString(): null argument or not an array.`n"
		return $null; 
	}
	if ("$($ArrayVar.GetType().BaseType.Name)" -ne "Array") 
	{ 
		Write-Host "`nError in ArrayToString(): not an array.`n"
		Write-Host "$($ArrayVar.GetType().BaseType.Name) instead of 'Array'`n"
		return $null; 
	}
	$count = $ArrayVar.Count;
	$sb = New-Object -TypeName "System.Text.StringBuilder";
	# Remark: Assignments $null = 
	$null = $sb.Append("@(");
	foreach ($ind in ( (0..$($count-1)) )  )
	{
		# Write-Host $sb.ToString()
		$null = $sb.Append($ArrayVar[$ind]);
		if ($ind -lt $count-1)
		{
			$null = $sb.Append(", ");
		}
	}
	$null = $sb.Append(")");
	return $($sb.ToString());
}

function PrintArray($ArrayVar = $null)
{
	$str = ArrayToString $ArrayVar
	Write-Host "$str"
}

function DictionaryToString($DictVar = $null)
{
	if ("$DictVar" -eq "") { return "$null"; }
	foreach ($key in $dictionary.Keys) { 
		Write-Host "Key: $key    Value: $($dictionary[$key])" 
	} 
}



function RunWithPowerShell($Command)
{
	powershell.exe '#Command'
}

 
PowerShellInfo



