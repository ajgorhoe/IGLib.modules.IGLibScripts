
# ExpandTemplate.ps1 – User Manual

## Overview

`ExpandTemplate.ps1` is a **template expansion engine** written in PowerShell.  
It takes a text template file with **placeholders** (`{{ ... }}`) and expands them using **variables**, **environment variables**, and **filters**.

It is designed for:

* Generating configuration files
* Testing escape/unescape filters
* Automating documentation and scripts with parameterized text


## Syntax

~~~PowerShell
.\ExpandTemplate.ps1 `
    -Template <TemplateFile> `
    -Output <OutputFile> `
    [-Var <"Name=Value"[,...]>] `
    [-Variables <Hashtable>] `
    [-VarsFile <FileWithVars>] `
    [-Encoding <Encoding>] `
    [-Verbose] [-Debug]
~~~




## Parameters

### `-Template <string>`

Path to the template file (`*.tmpl`) that contains placeholders.

### `-Output <string>`

Path to the expanded output file.

### `-Var <array of strings>`

Inline variable assignments in the form `Name=Value`.  
Can be repeated multiple times, or passed as an array:

~~~PowerShell
-Var "Name1=Value1", "Name2=Value2"
-Var @("Name1=Value1", "Name2=Value2")
~~~

### `-Variables <hashtable>`

Hashtable of variables, e.g.:



~~~PowerShell
-Variables @{ Project="MyProj"; Version="1.2.3" }
~~~

### `-VarsFile <string>`

Optional file with variable assignments (line format: `Name=Value`).  
Values from `-Var` and `-Variables` override `-VarsFile`.

### `-Encoding <string>`

Encoding of the output file. Default: `UTF8`.

### `-Verbose` / `-Debug`

Enable detailed or very detailed tracing of placeholder parsing and filter application.

## Placeholders

### Format


~~~PowerShell
{{ head | filter1[:arg1[:arg2...]] | filter2 ... }}
~~~

-   **Head**:
    -   `var.Name` → variable defined via `-Var`, `-Variables`, or `-VarsFile`
    -   `env.NAME` → environment variable
-   **Filters**: Transformations applied left-to-right.
    

### Examples


~~~PowerShell
{{ var.Project }}               → expands to "MyProj"
{{ env.USERNAME | upper }}      → expands to uppercase user name
{{ var.PathWin | pathappend:"bin" }}
                                → expands to a path with "bin" appended
~~~









~~~PowerShell

~~~


~~~PowerShell

~~~


~~~PowerShell

~~~


~~~PowerShell

~~~


~~~PowerShell

~~~


~~~PowerShell

~~~


~~~PowerShell

~~~


~~~PowerShell

~~~


~~~PowerShell

~~~
