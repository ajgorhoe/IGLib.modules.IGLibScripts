#!/usr/bin/env dotnet-script

// This is a very simple test script to check that dotnet-script is working.
// It can be run with command: dotnet script ./test.csx

// Just as test, output the arguments passed to the script:
if (Args.Count == 0)
{
    Console.WriteLine("  No arguments passed to the script." + Environment.NewLine);
}
else
{
    Console.WriteLine($"{Args.Count} arguments passed to the script:");
    int i = 0;
    foreach (string arg in Args)
    {
        i++;
        Console.WriteLine($"  {i}: {arg}");
    }
    Console.WriteLine();
}

var a = 2;
var b = Math.Sqrt(a);
Console.WriteLine($"Square root of {a} is {b}.");

