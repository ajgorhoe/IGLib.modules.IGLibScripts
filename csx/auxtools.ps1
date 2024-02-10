# #!/usr/bin/env pwsh

# Preparation of auxliliary tools, such as auxiliary repositories.

$AuxiliaryDir = "$PSScriptRoot/auxiliary"

$RepoGLibScripts = "https://github.com/ajgorhoe/IGLib.modules.IGLibScripts.git"
$RepoDirGLibScripts = "$AuxiliaryDir/IGLibScripts"
$RepoBranchGLibScripts = "master"

$RepoIGLibCore = "https://github.com/ajgorhoe/IGLib.modules.IGLibCore.git"
$RepoDirIGLibCore = "$AuxiliaryDir/IGLibCore"
$RepoBranchIGLibCore = "master"
$IGLibCoreSolutionFile = "$RepoDirIGLibCore/IGLibCore.sln"
$IGLibCoreProjectFile = "$RepoDirIGLibCore/src/IGLibCore.csproj"
$IGLibCoreBinaryDir = "$RepoDirIGLibCore/src/bin/Debug/net6.0"


Write-Host
Write-Host "AuxiliaryDir: $AuxiliaryDir"
Write-Host "RepoGLibScripts: $RepoGLibScripts"
Write-Host "RepoDirGLibScripts: $RepoDirGLibScripts"
Write-Host "RepoBranchGLibScripts: $RepoBranchGLibScripts"
Write-Host
Write-Host "RepoIGLibCore: $RepoIGLibCore"
Write-Host "RepoDirIGLibCore: $RepoDirIGLibCore"
Write-Host "RepoBranchIGLibCore: $RepoBranchIGLibCore"
Write-Host


Write-Host "Cloning the IGLibScripts repository..."
. git clone -b "$RepoBranchGLibScripts" "$RepoGLibScripts" "$RepoDirGLibScripts"
Write-Host "  ... cloning IGLibScripts repository done."
Write-Host

Write-Host "Cloning the IGLibCore repository..."
. git clone -b "$RepoBranchIGLibCore" "$RepoIGLibCore" "$RepoDirIGLibCore"
Write-Host "  ... cloning IGLibCore repository done."
Write-Host

Write-Host "Building IGLibCore sources..."
. dotnet build "$IGLibCoreProjectFile" --configuration Debug
Write-Host "  ... building IGLibCore done."
