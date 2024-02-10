

// Loading a dependency - C# script, and verify that definitions are there:

#r "System"
using System;
using System.IO;


Console.WriteLine(Environment.NewLine + "Starting: dependency.csx");

string varDependencyCsx = "This string variable was defined in dependency.csx.";

Console.WriteLine("End: dependency.csx.")

