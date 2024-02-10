
// Uncomment definitions below to activate console outputs (this will cause compilation errors)
#define LoadedFromScript

using System;
using System.IO;


#if LoadedFromScript
Console.WriteLine(Environment.NewLine + "Beginning of dependency.cs." + Environment.NewLine);
#endif


public class DependencyClass
{

	public DependencyClass()
	{  }

	public static string DependencyClassType { get; } = typeof(DependencyClass).FullName;

	public static string DependencyClassTypeAQ { get; } = typeof(DependencyClass).AssemblyQualifiedName;

}


#if LoadedFromScript
Console.WriteLine(Environment.NewLine + "End of dependency.cs." + Environment.NewLine);
#endif

