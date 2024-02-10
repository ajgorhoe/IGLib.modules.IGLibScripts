
@echo off

rem Installs the dotnet-script.

echo.
echo Installing dotnet-script tool (scripting shell)...
dotnet dotnet tool install -g dotnet-script

echo.
echo ... installed.
echo.
echo To uninstall dotnet-script, call:
echo   otnet tool uninstall dotnet-script -g

echo run with:
echo   dotnet script [file] -- param1 param2...
echo or:
echo   dotnet-script [file] --param1 param2...

echo To initialize script directory:
echo   dotnet script init
echo or:
echo   dotnet script init custom.csx



