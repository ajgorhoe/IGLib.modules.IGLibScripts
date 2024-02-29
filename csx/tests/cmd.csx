
#load "CommandLineUtilities.cs"

using System;

Console.WriteLine($"Type of the 'Args' variable containing command-line arguments: ${Args.GetType().Name}\n");
Console.WriteLine($"Calling the script for printing command-line arguments...");
Console.WriteLine($"======================== Printing command-liine args...");
PrintCommandlineArguments();
Console.WriteLine($"======================== ");

do
{
    Console.WriteLine("Enter command with parameters, or empty string do stop the program:
    string cmsLine = Console.ReadLine()");
}

public void PrintCommandlineArguments(IList<string> cmdArgs = null)
{
    if (cmdArgs == null)
    {
        cmdArgs = Args;
    }

    Console.WriteLine($"Command-line arguments ({cmdArgs?.Count} arguments):");
    if (cmdArgs == null)
    { Console.WriteLine($"  null"); }
    else if (cmdArgs.Count <= 0)
    { Console.WriteLine($"  Empty argument list."); }
    else 
    {
        for (int i = 0; i < cmdArgs.Count; i++)
        {
        
            Console.WriteLine(@$"  {i}: ""{cmdArgs[i]}""");
        }
    }
}

