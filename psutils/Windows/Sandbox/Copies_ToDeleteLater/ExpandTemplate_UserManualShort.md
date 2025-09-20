
# ExpandTemplate.ps1 – User Manual

## Overview

`ExpandTemplate.ps1` is a **template expansion engine** written in PowerShell.  
It takes a text template file with **placeholders** (`{{ ... }}`) and expands them using **variables**, **environment variables**, and **filters**.

It is designed for:

* Generating configuration files
* Testing escape/unescape filters
* Automating documentation and scripts with parameterized text

## Syntax

~~~powershell
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

~~~powershell
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


~~~text
{{ head | filter1[:arg1[:arg2...]] | filter2 ... }}
~~~

* **Head**:
  * `var.Name` → variable defined via `-Var`, `-Variables`, or `-VarsFile`
  * `env.NAME` → environment variable
* **Filters**: Transformations **applied left-to-right**.
  * **Filter arguments**: separated by colon `:`, stated in double quotes, or not quoted if they don't contain whitespace characters or colon `:` or vertical line `|` or open curly bracket `{`; when in double quotes, you can use escape sequences `\"` `\\` for backslash `\` or `\"` for double quote `"` (`\` followed by other characters is taken literally, such as `\a` or `\.`, which makes possible to state Windows paths without escaping)

### Examples

~~~text
{{ var.Project }}               → expands to "MyProj"
{{ env.USERNAME | upper }}      → expands to uppercase user name
{{ var.PathWin | pathappend:"bin" }}
                                → expands to a path with "bin" appended
~~~

## Filters

### String Manipulation

* `lower` – convert to lowercase
* `upper` – convert to uppercase
* `trim` – trim whitespace
* `append:Text` – append text
* `prepend:Text` – prepend text
* `replace:Old:New` – replace substring
    

### Path Handling

* `pathappend:Part` – append path component
* `pathwin` / `pathwinabs` – normalize to Windows path
* `pathlinux` / `pathlinuxabs` – normalize to Linux path
* `pathos` / `pathosabs` – normalize to current OS
* `pathquote` – quote path safely
    

### Escaping/Encoding

* `esccs` / `fromesccs` – C# escaping
* `escjava` / `fromescjava` – Java escaping
* `escc` / `fromescc` – C/C++ escaping
* `urlenc` / `urldec` – URL encoding/decoding
* `xmlenc` / `xmldec` – XML escaping/unescaping
* `regq` – regex quoting
* `regesc` – regex escaping

### Examples

~~~text
{{ var.MyVarSimple | append:"_end" }}
 → "value_end"

{{ var.MyVarLong | replace:"demo":"test" | upper }}
 → all "demo" replaced with "test", result in uppercase

{{ var.PathWin | pathappend:"dir1\dir2\file.txt" | replace:"\\":"/" }}
 → normalized Unix-style path
~~~

## Unquoted Filter Arguments

Filter arguments **do not need quotes** if they contain only:

* letters, digits, underscores
* no whitespace
* no `:`, `|`, or `}`
    

Examples:

~~~text
{{ var.MyVarSimple | append:suffix }}
{{ var.PathWin | replace:\\:/ }}
~~~

Quoted form is still valid (and required if spaces or special chars are present):

~~~text
{{ var.MyVarSimple | append:suffix }}
{{ var.PathWin | replace:\\:/ }}
~~~

Quoted form is still valid (and required if spaces or special chars are present):

~~~text
{{ var.MyVarSimple | append:" with space" }}
~~~

## Escaping Placeholders

To emit literal `{{` or `}}` in the output:

* use `\{{` to emit `{{`, and `\}}` to emit `}}`
* or use `\{\{` to emit `{{`, and `\}\}` to emit `}}`

~~~text
\{{     → outputs {{
\}}     → outputs }}
\{\{    → outputs {{
\}\}    → outputs }}
~~~

The second form is is used when you need to be more unambiguous, because it does not contain the targeted output sequences `{{` or `}}`, which have a special meaning.

**To verify** - is this also valid?

~~~text
{{ "{{" }} → outputs {{
{{ "}}" }} → outputs }}
~~~

## Error Handling

* Unknown filters → error with filter name
* Unclosed placeholders → error with position
* Null input to filters → warning/error depending on context
* Variables not found → empty string

## Example

Template (`example.tmpl`):

~~~text
Project: {{ var.Project }}
User:    {{ env.USERNAME | upper }}
Path:    {{ var.PathWin | pathappend:bin | replace:\\:/ }}
Escaped: {{ var.Special | escc }}
~~~

Call:

~~~powershell
.\ExpandTemplate.ps1 `
  -Template example.tmpl `
  -Output example.txt `
  -Var "Project=DemoApp" `
  -Variables @{ PathWin="C:\apps\demo\"; Special="A\nB" }
~~~

Output (`example.txt`):

~~~PowerShell
Project: DemoApp
User:    ADMINUSER
Path:    C:/apps/demo/bin
Escaped: A\nB
~~~

## Notes & Best Practices

* Use `-Debug` to trace placeholder parsing and filter pipelines.
* Use `-Verbose` for higher-level overview.
* Prefer quoted arguments unless you’re confident about unquoted safety.
* Keep template files in version control; generated files should not be checked in.

