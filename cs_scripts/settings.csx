#!/usr/bin/env dotnet-script

#load "tools.csx"

using System;
using System.Collections;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Authentication.ExtendedProtection;
using System.Security.Policy;




/// <summary>Returns the binary directory of the service of the current repository with the specified
/// <paramref name="projectName"/>. This is only successful if the service directory name equals the
/// service name and the service is build (i.e., DLLs exist in one of the expected binary directories).</summary>
/// <param name="projectName">Name of the service, should be the same as name of the project and DLL file.</param>
/// <param name="forceRelease">If true then only release binaries are considered; if not then Debug binaries
/// have priority over release binaries.</param>
public static string GetServiceBinaryDir(string projectName, bool forceRelease = false)
{
    return GetBinaryDir(CombinePath(GetScriptDirectory(), "../", projectName), forceRelease);
}

/// <summary>Returns the path of the service DLL.</summary>
/// <seealso cref="GetServiceBinaryDir(string, bool)"/>
public static string GetServiceDll(string projectName, bool forceRelease = false)
{
    string binPath = CombinePath(GetServiceBinaryDir(projectName, forceRelease), projectName + ".dll");
    if (File.Exists(binPath))
        return binPath;
    return null;
}

/// <summary>Returns the path of the service executable.</summary>
/// <seealso cref="GetServiceBinaryDir(string, bool)"/>
public static string GetServiceExecutable(string projectName, bool forceRelease = false)
{
    string binPath = CombinePath(GetServiceBinaryDir(projectName, forceRelease), projectName + ".exe");
    if (File.Exists(binPath))
        return binPath;
    return null;
}

/// <summary>Loads the assemblies of the service named <paramref name="projectName"/> (both .dll and .exe)
/// if they exists. Returns true if successfully loaded, false otherwise.</summary>
/// <seealso cref="GetServiceBinaryDir(string, bool)"/>
public static bool LoadServiceAssemblies(string projectName, bool forceRelease = false)
{
    bool isDllLoaded = false;
    bool isExeLoaded = false;
    try
    {
        string dllPath = GetServiceDll(projectName, forceRelease);
        if (File.Exists(dllPath))
        {
            var loaded = Assembly.LoadFrom(dllPath) != null;
            if (loaded)
            {
                isDllLoaded = true;
                Console.WriteLine($"Loaded service asssembly (dll) from: \n  {dllPath}");
            }
        }
        if (false)
        {
            // ToDo: cannot load .exe assemblies. Check why.
            // Possible hint: https://learn.microsoft.com/en-us/dotnet/core/compatibility/sdk/5.0/referencing-executable-generates-error
            string exePath = GetServiceExecutable(projectName, forceRelease);
            if (File.Exists(exePath))
            {
                var loaded = Assembly.LoadFrom(exePath) != null;
                if (loaded)
                {
                    isExeLoaded = true;
                    Console.WriteLine($"Loaded service asssembly (exe) from: \n  {exePath}");
                }
            }
        }
    }
    catch(Exception ex)
    {
        Console.WriteLine($"Exception {ex.GetType().Name} when loading service assemblies for {projectName}: \n  {ex.Message}");
    }
    if (!(isDllLoaded || isExeLoaded))
    {
        Console.WriteLine($"\nWARNING: Could not load assemblies for service {projectName} .\n");
        return false;
    }
    return true;
}

/// <summary>Loads assemblies for a set of services (<paramref name="projectNames"/>) by using
/// <see cref="LoadServiceAssemblies(string, bool)"/>, with Debug versions prioritized.</summary>
/// <seealso cref="LoadServiceAssemblies(string, bool)"/>
public static void LoadProjectAssemblies(params string[] projectNames)
{
    foreach(string projectName in projectNames)
    {
        LoadServiceAssemblies(projectName, forceRelease: false);
    }
}

/// <summary>Loads release assemblies for a set of services (<paramref name="projectNames"/>) by using
/// <see cref="LoadServiceAssemblies(string, bool)"/> (only Release versions are considered).</summary>
/// <seealso cref="LoadServiceAssemblies(string, bool)"/>
public static void LoadProjectReleaseAssemblies(params string[] projectNames)
{
    foreach(string projectName in projectNames)
    {
        LoadServiceAssemblies(projectName, forceRelease: true);
    }
}










