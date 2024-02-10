#!/usr/bin/env dotnet-script

#load "tstdev.csx"

using System;


Console.WriteLine($"\nFrom rst.csx:\n");

Console.WriteLine($"GetCurrentTime(): {GetCurrentTime()}");
Console.WriteLine($"time: {time}");

Console.WriteLine("Script related definitions imported from settings.csx:");
Console.WriteLine($"GetScriptPath(): {GetScriptPath()}");
Console.WriteLine($"GetScriptDirectory(): {GetScriptDirectory()}");
Console.WriteLine($"GetScriptFileName(): {GetScriptFileName()}");

Console.WriteLine($"scriptfile: {scriptfile}");
Console.WriteLine($"scriptdir: {scriptdir}");
Console.WriteLine($"lastscriptfile: {lastscriptfile}");
Console.WriteLine($"lastscriptdir: {lastscriptdir}");




