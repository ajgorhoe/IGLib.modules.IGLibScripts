
# Directory Viewer Project

The **directory viewer C# project** ([./IG.Scripts.DirectoryViewer.csproj](./IG.Scripts.DirectoryViewer.csproj)) has been created to be included in Visual Studio's solution and in other .NET IDEs (Integrated Development Environments) such that **contents of the** repository **directory can be browsed** in the respective IDEs, such as in *Visual Studio's Solution Explorer*.

In order to **not interfere** with usual workflows and other tools and to **be unobtrusive**, the project file is **put to its own directory**, which is placed in another subdirectory of the repository (and not in the repository root).

A Visual Studio [solution file](./DirectoryViewer.sln) is included to test the project. There are several versions of the project included in the VS solution for testing ([./DVFiles/v1.csproj](./DVFiles/v1.csproj), [./DVFiles/v2.csproj](./DVFiles/v2.csproj), [./DVFiles/Newer.csproj](./DVFiles/Newer.csproj)) to test possible variations. These projects are configured such that they show files from the parent directory, while the [IG.Scripts.DirectoryViewer.csproj](./IG.Scripts.DirectoryViewer.csproj) is configured to show the repository root directory (the parent of the parent directory).

There are some deficiencies of the approach, i.e., the files included in the project directory are not shown correctly: either they are not shown at all, or are shown as if they were included directly in the directory that is displayed.

## About Dummy Projects for Listing Directory Contents in .NET IDEs

The purpose is to (recursively) **show contents of an arbitrary directory in an IDE** (Integrated Development Environment) that supports .NET development, such that files within the entire directory structure can be browsed and files opened in the IDE, e.g. **in Visual Studio's Solution Explorer**. One way to achieve this is **via a specially configured C# code project**. For this purpose, one needs to achieve that all files contained in the specific directories and recursively its subdirectories are included as part of project, but at the same time these files need to be excluded from any build tasks; if possible, any build-related actions should be prevented completely.

