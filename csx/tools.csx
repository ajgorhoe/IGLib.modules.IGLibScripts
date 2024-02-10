#!/usr/bin/env dotnet-script

#region References

#r "System.Net.HTTP"

using System;
using System.Text;
using System.Reflection;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Collections;
using System.Collections.Generic;
using System.Collections.Concurrent;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Linq;
using System.Runtime.CompilerServices;

#endregion References



#region ScriptingSupport


public static DateTime GetCurrentTime() => DateTime.Now;

/// <summary>Gets the current time.</summary>
public static DateTime time => GetCurrentTime();

public static string NormalizePath(string path)
{
    if (string.IsNullOrEmpty(path))
    { path = ".";  }
    return Path.GetFullPath(path)?.Replace(@"\", @"/");
}

/// <summary>Returns the file path of the currently executing script.</summary>
/// <param name="path">Dummy parameter, not used.</param>
public static string GetScriptPathNotNormalized([CallerFilePath] string path = null)
    => path;

/// <summary>Returns the file path of the currently executing script.</summary>
/// <param name="path">Dummy parameter, not used.</param>
public static string GetScriptPath([CallerFilePath] string path = null)
    => NormalizePath(path);

public static string scriptpath => GetScriptPath();

/// <summary>Returns the file name of the currently executing script.</summary>
/// <param name="path">Dummy parameter, not used.</param>
public static string GetScriptFileName([CallerFilePath] string path = null)
    => Path.GetFileName(path);

/// <summary>Returns the containing directory path of the currently executing script.</summary>
/// <param name="path">Dummy parameter, not used.</param>
public static string GetScriptDirectory([CallerFilePath] string path = null)
    => Path.GetDirectoryName(path);

/// <summary>Evaluates to the path of the containing directory of the currently executing script.</summary>
public string scriptdir => GetScriptDirectory();

/// <summary>Evaluates to the file name of the currently executing script.</summary>
public string scriptfile { get { return GetScriptFileName(); } }

/// <summary>Gets the path of the containing directory of the last executing script
/// (distinction between the last and the currently executing is important in REPL environments).</summary>
public static string lastscriptdir { get; } = GetScriptDirectory();

/// <summary>Gets the file name of the last executing script
/// (distinction between the last and the currently executing is important in REPL environments).</summary>
public static string lastscriptfile { get; } = GetScriptFileName();


#endregion nScriptingSupport


if (Environment.GetEnvironmentVariable(
    "hasbeenloaded_baseref") != null)
{
    Console.WriteLine($"\nThis script has already been run: {GetScriptFileName()}\n");
}


#region SystemEnvironment

/// <summary>Environment variables manipulation.</summary>
public class Env
{
    public string this[string varName]
    {
        get {
            if (string.IsNullOrEmpty(varName)) { return null; }
            return Environment.GetEnvironmentVariable(varName);
        }
        set { if (!string.IsNullOrEmpty(varName))
                Environment.SetEnvironmentVariable(varName, value);
        }
    }
    //public string this[object varName]
    //{
    //    set { this[varName.ToString] = value.ToString(); }
    //    get { return this[varName.ToString()]; }
    //}
    public void set(string varName, string value)
    {
        this[varName] = value;
    }
    public string get(string varName) => this[varName];
    public bool def(string varName)
    { return this[varName] != null; }
}



public static Env env = new Env();
public static bool envdef(string varName) => env.def(varName);

/// <summary>Sets the environment variable named <paramref name="name"/> to <paramref name="value"/>,
/// if not null or empty. Returns the current value of hte environment variable, or null if <paramref name="name"/> is null or empty.</summary>
public static string envf(string name, string value = null)
{
    if (!string.IsNullOrEmpty(name))
    {
        if (!string.IsNullOrEmpty(value))
        {
            Environment.SetEnvironmentVariable(name, value);
        }
        return Environment.GetEnvironmentVariable(name);
    }
    return null;
}


/// <summary>Changes current directory to <paramref name="path"/> (if specified; can be absolute or relative)
/// and returns the canonical absolute path to the current directory.</summary>
/// <param name="path"></param>
/// <returns></returns>
public static string cdf(string path = null)
{
    if (!string.IsNullOrEmpty(path))
    {
        Directory.SetCurrentDirectory(Path.GetFullPath(path));
    }
    return Directory.GetCurrentDirectory();
}

public static string cd {
    get { return Directory.GetCurrentDirectory(); }
    set {
        if (string.IsNullOrEmpty(value))
        {
            Console.WriteLine("Current directory not changed.");
        } else
        {
            string path = Path.GetFullPath (value);
            if (Directory.Exists(path))
            {
                Directory.SetCurrentDirectory(path);
            } else
            {
                Console.WriteLine("Directory does not exist, current directory not changed.");
            }
        }
        Console.WriteLine("CD: " + Directory.GetCurrentDirectory());
    }
}

/// <summary>Writes to console concatenated string parameters.</summary>
/// <param name="args"></param>
public static void p(params string[] args)
{
    if (args == null || args.Length == 0)
    {
        Console.WriteLine();
    }
    else
    {
        Console.WriteLine(string.Join(" ", args));
    }
}

/// <summary>Writes the assigned string to console.</summary>
public static string pr { set { p(value); } }
public static string prn { set { p(value); } }


/// <summary>Combines parts of file or directory path and returns combined absolute path in canonical form.
/// If all parts are null or empty then current directory's path is returned.</summary>
/// <param name="path1">First part of the path (usually directory path).</param>
/// <param name="path2">Second part of the path (usually directory path relative to <see cref="path1"/>)</param>
/// <param name="filenameOrExtension">File or directory name. Can be null if this part is incorporated in previous parts.</param>
/// <returns></returns>
public static string CombinePath(string path1 = null, string path2 = null,
    string filenameOrExtension = null)
{
    string path = null;
    if (!string.IsNullOrEmpty(path1))
    {
        if (!string.IsNullOrEmpty(path2))
        {
            path = Path.GetFullPath (Path.Combine(path1, path2));
        } else
        {
            path = Path.GetFullPath(path1);
        }
    } else if (!string.IsNullOrEmpty(path2))
    {
        path = Path.GetFullPath(path2);
    }
    if (!string.IsNullOrEmpty(filenameOrExtension))
    {
        if (!string.IsNullOrEmpty(path))
        {
            path = Path.GetFullPath(Path.Combine(path, filenameOrExtension));
        }
        else
        {
            path = Path.GetFullPath(filenameOrExtension);
        }
    }
    if (string.IsNullOrEmpty(path))
    {
        path = Path.GetFullPath(Directory.GetCurrentDirectory());
    }
    return path;
}

/// <summary>The same as (REPL alias) <see cref="GetPath(string, string, string)"/>.</summary>
public static string path(string path1 = null, string path2 = null, string filenameOrExtension = null)
{ return CombinePath(path1, path2, filenameOrExtension); }

#endregion SystemEnvironment


#region ReferencingProjectBinaries



public static string[] BinaryDirsDebugRelative { get; } = new string[]
{
    "bin//Debug/net5.0",
    "bin//Debug/net6.0",
    "bin//Debug/net7.0"
};

public static string[] BinaryDirsReleaseRelative { get; } = new string[]
{
    "bin//Release/net5.0",
    "bin//Release/net6.0",
    "bin//Release/net7.0"
};

public static string GetBinaryDir(string projectPath, bool forceRelease = false)
{
    if (string.IsNullOrEmpty(projectPath))
    { throw new ArgumentException("Project path not specified.", nameof(projectPath)); }
    if (!Directory.Exists(projectPath))
    { throw new ArgumentException($"Project directory does not exist: \n{projectPath} ", nameof(projectPath)); }
    string[] relativeDirs = null;
    if (forceRelease)
    {
        relativeDirs = BinaryDirsReleaseRelative;
    } else
    {
        relativeDirs = BinaryDirsDebugRelative.Concat(BinaryDirsReleaseRelative).ToArray();
    }
    // Try to find binaries directory from debug:
    foreach (string dir in relativeDirs)
    {
        string trialDir = Path.Combine(projectPath, dir);
        if (Directory.Exists(trialDir))
        {
            string[] files = Directory.GetFiles(trialDir, "*.dll");
            if (files != null && files.Length > 0)
            {
                return trialDir;
            }
        }

    }
    return null;
}



#endregion  ReferencingProjectBinaries



// List of useful assemblies to make scripting easier, taken from:
// https://github.com/RickStrahl/Westwind.Scripting

#if NET

    // Loading .NET base libraries:
    Console.WriteLine(Environment.NewLine + "Loading .NET basic assemblies...");

#r "System.Private.CoreLib.dll"
#r "System.Runtime.dll"
#r "System.Console.dll"
#r "netstandard.dll"
#r "System.Text.RegularExpressions.dll"
#r "System.Linq.dll"
#r "System.Linq.Expressions.dll"
#r "System.IO.dll"
#r "System.Net.dll"
#r "System.Net.Primitives.dll"
#r "System.Net.Http.dll"
#r "System.Private.Uri.dll"
#r "System.Reflection.dll",
#r "System.ComponentModel.Primitives.dll"
#r "System.Globalization.dll"
#r "System.Collections.Concurrent.dll"
#r "System.Collections.NonGeneric.dll"
#r "Microsoft.CSharp.dll"


    // Loading .NET base libraries:
    Console.WriteLine(Environment.NewLine + "Loading .NET basic assemblies...");

#elif NETFRAMEWORK

    // Loading .NET Framework base libraries:
    Console.WriteLine(Environment.NewLine + "Loading .NET Framework basic assemblies...");

#r "mscorlib.dll"
#r "System.dll"
#r "System.Core.dll"
#r "Microsoft.CSharp.dll"
#r "System.Net.Http.dll"

#endif


env["hasbeenloaded_tools"] = "true";





