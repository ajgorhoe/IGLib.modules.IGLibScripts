<#
.SYNOPSIS
    Enables or disables full classic context menus in Windows 11.

.DESCRIPTION

.PARAMETER Revert
    Reverts to the default "Show more options" behavior.

.PARAMETER RestartExplorer
    Restarts the Explorer process after making changes to apply them immediately.

.PARAMETER AllUsers
    Applies the registry change to all existing users on the system (requires elevation).
    If not elevated, a prompt is shown. If elevation is denied, a warning is issued and the change is applied to the current user only.

.EXAMPLE
    .\ShowFullContextMenus.ps1
    Enables full context menus for current user.

.EXAMPLE
    .\ShowFullContextMenus.ps1 -Revert -RestartExplorer
    Reverts to default behavior and restarts Explorer.

.EXAMPLE
    .\ShowFullContextMenus.ps1 -AllUsers
    Enables full context menus for all users (requires admin).

.EXAMPLE
    .\ShowFullContextMenus.ps1 -Revert -AllUsers -RestartExplorer
    Reverts to default behavior for all users and restarts Explorer.
#>

param (
    [switch]$Revert,
    [switch]$RestartExplorer,
    [switch]$AllUsers
)

