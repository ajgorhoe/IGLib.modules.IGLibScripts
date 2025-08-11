
# This script adds "Open with VS Code" to the Windows Explorer context menu
# for the current user, with more straight-forward code than the combination of
# AddCodeToExplorerMenu.ps1 and AddContextMenuItem.ps1, but with some 
# limitations (no -AllUsers, no -Revert)

$code = '%LOCALAPPDATA%\Programs\Microsoft VS Code\Code.exe'
reg add "HKCU\Software\Classes\*\shell\Open_with_VS_Code" /ve /d "Open with VS Code" /f
reg add "HKCU\Software\Classes\*\shell\Open_with_VS_Code" /v MUIVerb /t REG_SZ /d "Open with VS Code" /f
reg add "HKCU\Software\Classes\*\shell\Open_with_VS_Code" /v Icon /t REG_EXPAND_SZ /d $code /f
reg add "HKCU\Software\Classes\*\shell\Open_with_VS_Code\command" /ve /t REG_EXPAND_SZ /d "`"$code`" `"%1`"" /f
