
echo off
rem Windows command file; creates the trash_contents/ and save/
rem subdirectories, removes contents of trash_contents/

echo Removing all directories from the trash directory...

setlocal
cd %~dp0
rd /s /q trash_contents
md trash_contents
md save
endlocal


REM rd /s /q \users\0000trash\trash_contents

REM md \users\0000trash\trash_contents




