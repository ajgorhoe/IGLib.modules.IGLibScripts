
#r "..\..\..\..\..\output\bin\AnyCPU\Debug\IGLibCore.dll"
#r "..\..\..\..\..\output\bin\AnyCPU\Debug\IGLib.dll"

// Loading a library via Nuget (define package version for caching):

using System;
using System.IO;

using IG.Lib;
using IG.Num;

Console.WriteLine(Environment.NewLine + "Script exrefrelative.csx started.");



public class MathUtils: IG.Num.UtilMath
{ }
MathUtils instanceMU = new MathUtils();


// Use things defined in the loaded script file:
Console.WriteLine(Environment.NewLine + Environment.NewLine + "====" + Environment.NewLine
    + "Using definitions from loaded DLL (IGLibCore.dll)...");

Console.WriteLine(Environment.NewLine + "From DLL depencency: type of UtilMath = " + Environment.NewLine
    + "  \"" + typeof(UtilMath).FullName + "\"");
Console.WriteLine(Environment.NewLine + "Derived class instance type: (instanceMU.GetType()...) = " + Environment.NewLine
    + "  \"" + instanceMU.GetType().FullName + "\"");

var pi = UtilMath.pi;
Console.WriteLine(Environment.NewLine + "From loaded DLL: value of UtilMath.pi = " + Environment.NewLine
    + "  " + UtilMath.pi);
Console.WriteLine(Environment.NewLine + "From loaded DLL: check: UtilMath.pi - Math.PI = " + Environment.NewLine
    + "  " + (UtilMath.pi - Math.PI) );




Console.WriteLine(Environment.NewLine + "Script exrefrelative.csx ended.");

