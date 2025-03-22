# Prints variables used by repository updating/cloning script to fill
# unset parameters.

Write-Host "`n-------------------------------------------------------"
# Print all variables used as settings for updating / cloning repositories:
Write-Host "Variables for repository updating / cloning scripts:"
Write-Host "  CurrentRepo_Directory: $CurrentRepo_Directory"
Write-Host "  CurrentRepo_Ref:       $CurrentRepo_Ref"
Write-Host "  CurrentRepo_Address:   $CurrentRepo_Address"
Write-Host "  CurrentRepo_Remote:    $CurrentRepo_Remote"
Write-Host "  CurrentRepo_AddressSecondary: $CurrentRepo_AddressSecondary"
Write-Host "  CurrentRepo_RemoteSecondary:  $CurrentRepo_RemoteSecondary"
Write-Host "  CurrentRepo_AddressTertiary:  $CurrentRepo_AddressTertiary"
Write-Host "  CurrentRepo_RemoteTertiary:   $CurrentRepo_RemoteTertiary"
Write-Host "  CurrentRepo_ThrowOnErrors:    $CurrentRepo_ThrowOnErrors"

Write-Host "  CurrentRepo_DefaultFromVars:  $CurrentRepo_DefaultFromVars"
Write-Host "  CurrentRepo_BaseDirectory   : $CurrentRepo_BaseDirectory"

Write-Host "---------------------------------------------------------`n"
