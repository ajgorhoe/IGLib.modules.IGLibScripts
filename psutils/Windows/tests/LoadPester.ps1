
# This script installs and loads a recent Pester verson (at least v5).
# Run this script before running tests in this directory.

Write-Host "`nPreparing environment for Pester testing..."

# Check what we have installed:
Write-Host "`nChecking the currently installed modules..."
$modules = $(Get-Module Pester -ListAvailable | Select Name,Version,Path)
Write-Host "Installed modules:"
foreach ($m in $modules) {
  Write-Host "  $m"
}

# Install v5 (PSGallery must be reachable)
Write-Host "`nInstalling at least version 5 of Pester..."
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck ;

# Ensure v5 (at least) is the one loaded:
Write-Host "`nEnsuring that Pester v. at least 5 is loaded..."
Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.0.0

# Check again what we have installed:
Write-Host "`nRe-checking the currently installed modules..."
$modules = $(Get-Module Pester -ListAvailable | Select Name,Version,Path)
Write-Host "Installed modules:"
foreach ($m in $modules) {
  Write-Host "  $m"
}

Write-Host "`n  ... Pester environment prepared."
