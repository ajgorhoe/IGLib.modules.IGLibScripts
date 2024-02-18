
@echo off

rem Creates an executable from script.
rem Default script isi main.csx.

set ScriptDir=%~dp0
set ScriptFile=main.csx
if "%1" NEQ "" (
	set ScriptFile=%1
)
rem REMARK: OutputDir MUST NOT end with \
set OutputDir=%ScriptDir%\bin
set ScriptFilePath=%ScriptDir%\%ScriptFile%

echo.
echo Creating executable from %ScriptFile% ...
echo   Script file: %ScriptFile%
echo   Script file path: %ScriptFilePath%
echo   Output dir.: %OutputDir%
echo.

rem %ScriptFile%

cd %ScriptDir%
echo.
echo Running:
echo   dotnet script publish "%ScriptFilePath%"  -o "%OutputDir%"  -c Debug
echo   ...
dotnet script publish "%ScriptFilePath%"  -o "%OutputDir%"  -c Debug



