#!/usr/bin/env dotnet-script

// This is a very simple test script to check that dotnet-script is working.
// It can be run with command: dotnet script ./test.csx

var a = 2;
var b = Math.Sqrt(a);
Console.WriteLine($"Square root of {a} is {b}.");
