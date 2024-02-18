

/*
Below is how to run the script from different environments. Replace the scriptDir variable in code snippets 
to contain the containing directory of the script!
To run this script from command-line:
-------------
set scriptDir=c:\users1\igor\bat\bootstrappingscripts\IGLibScripts\cs_scripts\tests\
cd "%scriptDir%"
dotnet script tes.csx -- arg1 arg2 arg3 "arg 4" = + $$[] $${} $$()
// ...
#exit   //exit the interractive mode
// or, alternatively, omit the -i option in dotnet script
-------------
To run the script from dotnet script interactive or from VS's C# Interacrive:
-------------
var scriptDir = @"c:\users1\igor\bat\bootstrappingscripts\IGLibScripts\cs_scripts\tests\";
Directory.SetCurrentDirectory(scriptDir);
Directory.GetCurrentDirectory()
Args.Add("arg1"); Args.Add("arg2"); Args.Add("arg3"); Args.Add("arg 4"); Args.Add("="); Args.Add("+"); Args.Add("$$[]"); Args.Add(""); Args.Add("$${}"); Args.Add(""); Args.Add("$$()");
// ------------- After the above code - in a separate interactive REPL block:
#load "test.csx"
Directory.GetCurrentDirectory()
-------------
*/




using System;

Console.WriteLine($"Type of the 'Args' variable containing command-line arguments: ${Args.GetType().Name}\n");
Console.WriteLine($"Calling the script for printing command-line arguments...");
Console.WriteLine($"======================== Printing command-liine args...");
PrintCommandlineArguments();
Console.WriteLine($"======================== ");

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


/*
//The code below does not work, namespaces cannot be defined in C# scripts.
//When trying to execute the code, I get the following error message:
//error CS7021: Cannot declare namespace in script code


using System;

namespace MyNamespace
{
    public class MyClass
    {
        public void MyMethod()
        {
            Console.WriteLine("Hello from MyMethod!");
        }
    }

    public int myVariable = 42;

    public void PrintVariable()
    {
        Console.WriteLine($"The value of myVariable is: {myVariable}");
    }
}

// Access the class and variable from the defined namespace
MyNamespace.MyClass myObject = new MyNamespace.MyClass();
myObject.MyMethod();

MyNamespace.PrintVariable();
*/


