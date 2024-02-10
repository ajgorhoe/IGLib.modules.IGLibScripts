

// Loading dependencies - C# script & C# file, and veify that definitions are there:


#r "System"
// Loading a C# script file (.cs):
#load "dependency.csx"
// Loading a C# script (.csx)
#load "dependency.cs"

using System;
using System.IO;

Console.WriteLine(Environment.NewLine + "Script exloadscript.csx started.");

// Use things defined in the loaded script file:
Console.WriteLine(Environment.NewLine + Environment.NewLine + "====" + Environment.NewLine
    + "Using definitions from loaded C# SCRIPT file...");
Console.WriteLine(Environment.NewLine + "From SCRIPT depencency: varDependencyCsx = " + Environment.NewLine 
    + "  \"" + varDependencyCsx + "\"");

// Use things defined in the loaded C# file:
Console.WriteLine(Environment.NewLine + Environment.NewLine + "====" +Environment.NewLine
    + "Using definitions from loaded C# SOURCE file...");
Console.WriteLine(Environment.NewLine + "From depencency: DependencyClass.DependencyClassType = " + Environment.NewLine
    + "  \"" + DependencyClass.DependencyClassType + "\"");
Console.WriteLine(Environment.NewLine + "From depencency: DependencyClass.DependencyClassTypeAQ = " + Environment.NewLine
    + "  \"" + DependencyClass.DependencyClassTypeAQ + "\"");

Console.WriteLine(Environment.NewLine + "Script exloadscript.csx ended.");



