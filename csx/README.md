
# C# Scripts (Directory csx/) 

Copyright (c) Igor Grešovnik
See LICENSE.md at https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/

[IGLibScripts repository](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/blob/main/README.md) / [C# Script Utilities (directory csx/)](./README.md)

**Contents**:

* [Links](#links---c-scripting)
* [Running C# Scripts](#running-c-scripts)

## Links - C# Scripting

* [dotnet-script](https://github.com/dotnet-script/dotnet-script/blob/master/README.md) - utility used in `dotnet script` for running C# scripts or interactive Read-Evaluate-Print-Loop (REPL)
* [.NET Interactive](https://github.com/dotnet/interactive/blob/main/README.md) -  a more high level engine and API for running and editing code interactively; it is used as execution engine to build REPLs (like *[.NET REPL](https://github.com/jonsequitur/dotnet-repl)*), and in notebooks like [Jupyter](https://github.com/dotnet/interactive/blob/main/docs/NotebookswithJupyter.md) and [Polyglot](https://marketplace.visualstudio.com/items?itemName=ms-dotnettools.dotnet-interactive-vscode).

## Running C# Scripts

To run C# scrips, you need to install the [.NET SDK](https://dotnet.microsoft.com/en-us/download/dotnet) and then install the corresponding *.NET Core Global Tool* by running the command:

~~~shell
dotnet tool install -g dotnet-script
~~~

After this, you can check the installed .NET Core global tools (which also prints out the version of dotnet-script) by running the following command:

~~~shell
dotnet tool list -g
~~~

After `dotnet script` tool is installed, you can run C# statements in interactive mode by running either

~~~shell
dotnet script
~~~

or

~~~shell
dotnet-script
~~~

After running one of these commands, you can e.g. input the following commands (either line by line or by copy-pasting all at once):

~~~csharp
var a = 2;
var b = Math.Sqrt(a);
Console.WriteLine($"Square root of {a} is {b}.");
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

In this way, you execute C# scripts in interactive or REPL mode (Read-Evaluate-Print-Loop). In order **to execute a script file**, you just **add the script path** as parameter to command that runs the scripting engine, for example:

~~~shell
dotnet script ./test.csx
~~~~

You can also seed the REPL (interactive mode) with the script code by running the script with an -i flag:

~~~shell
dotnet script -i ./test.csx
~~~~

This seeds the REPL environment with the script before starting the interactive shell, meaning that variables, functions, and classes defined in the script file are accessible in the interactive shell. The same effect can be achieved by loading the script via `#load` command while already in the interactive mode:

~~~csharp
#load test.csx
~~~~

Directives (commands) like `#load` interpret paths that are not absolute as relative to the current directory (when executed in interactive mode) or as relative to the directory containing the script file where they are called.

If the `test.csx` contains the following code:

~~~csharp
var a = 2;
var b = Math.Sqrt(a);
Console.WriteLine($"Square root of {a} is {b}.");
~~~

then running the script in interactive shell in one of the described ways will make variables `a=2` and `b=1.4142135623730951` defined in the interactive shell. In **interactive mode**, you can use **relaxed syntax**, e.g., you can redefine variables, or you can type any legal C# expression, which will evaluate it and print its value. For example, you can do this:

~~~shell
.../csx> dotnet script
> int s = 12;
> s
12
> string s = "abc";
> s
"abc"
>
~~~

For more detailed and up-to-date information, **see the [dotnet-script README file](https://github.com/dotnet-script/dotnet-script/blob/master/README.md)**.
