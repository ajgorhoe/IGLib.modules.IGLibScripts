#!/usr/bin/env dotnet-script

/*
Below is how to run the script from different environments. Replace the scriptDir variable in code snippets 
to contain the containing directory of the script!
To run this script from command-line:
-------------
set scriptDir=c:\users1\igor\bat\bootstrappingscripts\IGLibScripts\cs_scripts\
cd "%scriptDir%"
dotnet script tests/testscript.csx -- arg1 arg2 arg3 "arg 4" = + $$[] $${} $$()
// ...
#exit   //exit the interractive mode
// or, alternatively, omit the -i option in dotnet script
-------------
To run the script from dotnet script interactive or from VS's C# Interacrive:
-------------
var scriptDir = @"c:\users1\igor\bat\bootstrappingscripts\IGLibScripts\cs_scripts\";
Directory.SetCurrentDirectory(scriptDir);
// Directory.GetCurrentDirectory().Replace(@"\", @"/");
Args.Add("arg1"); Args.Add("arg2"); Args.Add("arg3"); Args.Add("arg 4"); Args.Add("="); Args.Add("+"); Args.Add("$$[]"); Args.Add(""); Args.Add("$${}"); Args.Add(""); Args.Add("$$()");
var cd = Directory.GetCurrentDirectory();
// -------------  afterwards:
#load "main.csx"
#load "tests/testscript.csx"
-------------
*/


#load "settings.csx"
#load "tools.csx"


string loadedScript_main = GetScriptPath();
string lastLoadedScript = loadedScript_main;


Console.WriteLine("From mmain.csx: Autogenerate main (scaffolding with dotnet script init)");

