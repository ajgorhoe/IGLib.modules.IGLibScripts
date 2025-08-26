#!/usr/bin/env dotnet-script

using System.IO;
using System.Reflection;
using System.Runtime.CompilerServices;




// ******************************************************************************************************

// Utilities below are not finished yet and are not used at the moment.
// When finished, they may be added to testutils.csx and used in tests.csx.

public static List<Assembly> GetAssemblies(bool getLoaded = true, bool getEntryReferenced = true,
    bool getExecutingReferenced = true)
{
    Dictionary<Assembly, string> assemblies = new Dictionary<Assembly, string>();
    if (getLoaded)
    {
        try
        {
            Assembly[] loadedAssemblies = AppDomain.CurrentDomain.GetAssemblies();
            foreach (Assembly assembly in loadedAssemblies)
            {
                assemblies[Assembly] = assembly.FullName;
                Console.WriteLine($"Added loaded assembly: {assembly.GetName().Name}");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine("Adding loaded assemblies failed.")
        }
    }
    foreach (Assembly assembly in AppDomain.Getloaded)
        try
        {
            Assembly assembly = Assembly.GetExecutingAssembly();
            assemblies[assembly] = assembly.FullName;
            foreach (AssemblyName assemblyName in assembly.GetReferencedAssemblies())
            {
                try
                {
                    Assembly referencedAssembly = Assembly.Load(assemblyName);
                    assemblies[referencedAssembly] = referencedAssembly.FullName;
                }
                catch (Exception ex) { Console.WriteLine($"Loading assembly {assemblyName.Name} failed: {ex}"); }

            }
        }
        catch { "Assembly.GetExecutingAssembly() failed." }


    Assembly assembly = Assembly.GetExecutingAssembly();
    assembly.GetReferencedAssemblies();
    assembly.Getlo

    foreach (string typeName in typeNames)
    {

    }

    foreach (System.Reflection.AssemblyName an in System.Reflection.Assembly.GetExecutingAssembly().GetReferencedAssemblies())
    {
        System.Reflection.Assembly asm = System.Reflection.Assembly.Load(an.ToString());
        foreach (Type type in asm.GetTypes())
        {
            //PROPERTIES
            foreach (System.Reflection.PropertyInfo property in type.GetProperties())
            {
                if (property.CanRead)
                {
                    Response.Write("<br>" + an.ToString() + "." + type.ToString() + "." + property.Name);
                }
            }
        }
    }

    return null;

}



public static bool CheckTypesAvailability(params[] string typeNames)
{
    bool allTypesFound = true;

    return allTypesFound;
}

    







