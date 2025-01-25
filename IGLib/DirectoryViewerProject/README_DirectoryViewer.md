
# Directory Viewer Project

The **[diercyory viewer C# project](./IG.Scripts.DirectoryViewer.csproj)** has been created to be included in Visual Studio's solution and in other .NET IDEs (Integrated Development Environments) such that **contents of the** repository **directory can be browsed** in the respective IDEs, such as in *Visual Studio's Solution Explorer*.

In order to **not interfere** with usual workflows and other tools and to **be unobtrusive**, the project file is **put to its own directory**, which is placed in another subdirectory of the repository (and not in the repository root).

## About Dummy Projects for Listing Directory Contents in .NET IDEs

The purpose is to (recursively) **show contents of an arbitrary directory in an IDE** (Integrated Development Environment) that supports .NET development, such that files with entire directory structure can be browsed and opened, e.g. in Visual Studio's Solution Explorer. One way to achieve this is **via a specially configured C# code project**. For this purpose, one needs to achieve that all files contained in the specific directories and recursively its subdirectories are included as part of project, but at the same time these files need to be excluded from any build tasks; if possible, any build-related actions should be prevented completely.

