

#r "System"
#r "System.IO"
using System;
using System.IO;
using System.Security.Cryptography;

Console.WriteLine(Environment.NewLine +
  "Executing main.csx..." + Environment.NewLine);

//try
//{
//    Console.WriteLine(Environment.NewLine + "Type of this: " + this.GetType());
//    Console.WriteLine("Value of this: " + this.ToString() + Environment.NewLine);
//}
//catch (Exception ex)
//{
//    Console.WriteLine(Environment.NewLine + "Reference 'this' seems undefined. ERROR: "
//        + Environment.NewLine + "  " + ex.Message + Environment.NewLine);
//}

try
{
    System.Diagnostics.StackTrace stackTrace = new System.Diagnostics.StackTrace(true);
    string scriptFileName = stackTrace.GetFrame(0).GetFileName();
    Console.WriteLine(Environment.NewLine + "Script file: " + scriptFileName + "." + Environment.NewLine);

}
catch (Exception ex)
{
    Console.WriteLine(Environment.NewLine + "ERROR occurred when trying to obtain the script file path: "
        + Environment.NewLine + "  " + ex.Message + Environment.NewLine);
}

// Write eventual scritp arguments:
// To pass arguments to a scritp, execute it with th efollowing command:
//   dotnet script main.csx -- arg1 arg2 arg3 ...
// When run from application via ScriptEngine, you can define the string[] Args variable via scripting before
// running this file (e.g. via #load directive)
try
{
    Console.WriteLine(Environment.NewLine + "Script arguments: " + Environment.NewLine + "Type: " + Args?.GetType());
    int i = 0;
    foreach (var arg in Args)
    {
        ++i;
        Console.WriteLine("  Argument No. " + i + ": " + arg);
    }
}
catch(Exception ex)
{
    Console.WriteLine(Environment.NewLine + "ERROR when reading Args: " + ex.Message + Environment.NewLine);
}


// Perform some file system operations:
var CurrentDir = Directory.GetCurrentDirectory();
Console.WriteLine(Environment.NewLine + "Current directory: " + CurrentDir + Environment.NewLine);
var files = Directory.GetFiles(CurrentDir);
foreach (var filePath in files)
{
    string fileName = Path.GetFileName(filePath);
    var hash = HashAlgorithm.Create("SHA1")
        .ComputeHash(
        File.ReadAllBytes(filePath));
    Console.WriteLine("  file: " + fileName + ", hash: " + Environment.NewLine 
        + "    " + BitConverter.ToString(hash) );
}





Console.WriteLine(Environment.NewLine + "End of script: main.csx");

