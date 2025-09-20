
# This script installs and loads a recent Pester verson (at least v5).
# Run this script before running tests in this directory.

Write-Host "`nPreparing environment for Pester testing..."

# Check what you have:
Write-Host "`nChecking the currently installed modules..."
Get-Module Pester -ListAvailable | Select Name,Version,Path

# Install v5 (PSGallery must be reachable)
Write-Host "`Installing at least version 5 of Pester..."
Install-Module Pester -Scope CurrentUser -Force -SkipPublisherCheck

# Ensure v5 (at least) is the one loaded:
Write-Host "`nEnsuring that Pester v. at least 5 is loaded..."
Remove-Module Pester -ErrorAction SilentlyContinue
Import-Module Pester -MinimumVersion 5.0.0

# Chack again what you have:
Write-Host "`nRe-checking the currently installed modules..."
Get-Module Pester -ListAvailable | Select Name,Version,Path

Write-Host "`n  ... Pester environment prepared."
