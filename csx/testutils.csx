#!/usr/bin/env dotnet-script

using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;


public static DateTime GetCurrentTime() => DateTime.Now;

/// <summary>Gets the current time.</summary>
public static DateTime time => GetCurrentTime();

/// <summary>Returns the file path of the currently executing script.</summary>
/// <param name="path">Dummy parameter, not used.</param>
public static string GetScriptPath([CallerFilePath] string path = null)
    => path;
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






