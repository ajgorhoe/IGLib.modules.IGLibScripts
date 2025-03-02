# Prints variables used by repository updating/cloning script to fill
# unset parameters.

# Write-Host "`n-------------------------------------------------------"
Write-Host "`n-------------------------------------------------------"
Write-Host "Variables for repository updating / cloning scripts:`n"
Write-Host "  RepositoryDirectory: $RepositoryDirectory"

# Print variable values:

Write-Host "  RepositoryDirectory: $RepositoryDirectory"
Write-Host "  RepositoryRef:       $RepositoryRef"
Write-Host "  RepositoryAddress:   $RepositoryAddress"
Write-Host "  RepositoryRemote:    $RepositoryRemote"
Write-Host "  RepositoryAddressSecondary: $RepositoryAddressSecondary"
Write-Host "  RepositoryRemoteSecondary:  $RepositoryRemoteSecondary"
Write-Host "  RepositoryAddressTertiary:  $RepositoryAddressTertiary"
Write-Host "  RepositoryRemoteTertiary:   $RepositoryRemoteTertiary"
Write-Host "  RepositoryThrowOnErrors:    $RepositoryThrowOnErrors"

Write-Host "  RepositoryDefaultFromVars:  $RepositoryDefaultFromVars"
Write-Host "  RepositoryBaseDirectory   : $RepositoryBaseDirectory"

Write-Host "---------------------------------------------------------`n"
