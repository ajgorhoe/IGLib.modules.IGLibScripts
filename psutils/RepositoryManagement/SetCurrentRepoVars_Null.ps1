
# Resets repository update / clone settings

## Removing variables in a single shot:
# Remove-Variable -Name CurrentRepo_* -Scope Global

# Removing variables one by one:
$global:CurrentRepo_Directory        = $null
$global:CurrentRepo_Ref              = $null
$global:CurrentRepo_Address          = $null
$global:CurrentRepo_Remote           = $null
$global:CurrentRepo_AddressSecondary = $null
$global:CurrentRepo_RemoteSecondary  = $null
$global:CurrentRepo_AddressTertiary  = $null
$global:CurrentRepo_RemoteTertiary   = $null
$global:CurrentRepo_ThrowOnErrors    = $null
$global:CurrentRepo_DefaultFromVars  = $null
$global:CurrentRepo_BaseDirectory    = $null
