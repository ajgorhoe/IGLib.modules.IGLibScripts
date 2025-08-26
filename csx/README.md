
# C# Scripts (Directory csx/) 

Copyright (c) Igor Grešovnik
See LICENSE.md at https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/

[IGLibScripts repository](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/README.md) / [C# Script Utilities (directory csx/)](./README.md)

**Contents**:

* [Links](#links---c-scripting)
* [Running C# Scripts](#running-c-scripts)

## Links - C# Scripting

* [dotnet script repository](https://github.com/dotnet-script/dotnet-script/blob/master/README.md) - utility used in `dotnet script`
* [.NET Interactive] ia a more high level engine and API for running and editing code interactively; it is used as execution engine to build REPLs (like *[.NET REPL](https://github.com/jonsequitur/dotnet-repl)*), and in notebooks like [Jupyter](https://github.com/dotnet/interactive/blob/main/docs/NotebookswithJupyter.md) and [Polyglot](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.dotnet-interactive-vscode).

## Running C# Scripts

To run C# scrips, you need to install the [.NET SDK](https://dotnet.microsoft.com/en-us/download/dotnet) and then install the corresponding .NET Core Global Tool by running

~~~shell
dotnet tool install -g dotnet-script
~~~

After this, you can run C# statements in interactive mode by running either

~~~shell
dotnet script
~~~

or

~~~shell
dotnet-script
~~~

After running one of these commands, you can e.g. input the following commands:

~~~csharp
var a = 2;
var b = Math.Sqrt(a);
a
b
Console.WriteLine($"Square root of {a} ia {b}.");
#exit
~~~

The `#exit` directive (command) causes interactive shell to exit. You can use several other directives in C# scripts or interactive mode:

| Command  | Description                                                  |
| -------- | ------------------------------------------------------------ |
| `#load`  | Load a script into the REPL (same as `#load` usage in CSX)   |
| `#r`     | Load an assembly into the REPL (same as `#r` usage in CSX)   |
| `#reset` | Reset the REPL back to initial state (without restarting it) |
| `#cls`   | Clear the console screen without resetting the REPL state    |
| `#exit`  | Exits the REPL                                               |

See the [dotnet-script README](https://github.com/dotnet-script/dotnet-script/blob/master/README.md) for more detailed information.
