
#r "..\..\..\..\..\iglib\modules\IGLibCore\bin\Debug\net5.0\IGLibCore.dll"
// Loading a library via Nuget (define package version for caching):

using System;
using System.IO;

using IG.Lib;
using IG.Num;

Console.WriteLine(Environment.NewLine + "Script exrefrelative.csx started.");



public class Me: IG.Num.M
{ }
Me instanceMe = new Me();


// Use things defined in the loaded script file:
Console.WriteLine(Environment.NewLine + Environment.NewLine + "====" + Environment.NewLine
    + "Using definitions from loaded DLL (IGLibCore.dll)...");

Console.WriteLine(Environment.NewLine + "From DLL depencency: type of M = " + Environment.NewLine
    + "  \"" + typeof(M).FullName + "\"");
Console.WriteLine(Environment.NewLine + "Derived class instance type: (instanceMe.GetType()...) = " + Environment.NewLine
    + "  \"" + instanceMe.GetType().FullName + "\"");

var pi = M.pi;
Console.WriteLine(Environment.NewLine + "From loaded DLL: value of M.pi = " + Environment.NewLine
    + "  " + M.pi);
Console.WriteLine(Environment.NewLine + "From loaded DLL: check: M.pi - Math.PI = " + Environment.NewLine
    + "  " + (M.pi - Math.PI) );




Console.WriteLine(Environment.NewLine + "Script exrefrelative.csx ended.");

