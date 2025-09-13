
# PowerShell Template Engine

## PowerShell Template Engine (`ExpandTemplate.ps1`)

**Description**
Generates final files from templates (`.tmpl`) by expanding dynamic placeholders. This enables the user to create files (templates) with parameterized content, which depend on user-provided values (via script argument, in form of variables) or on environment variables.

Substitution of environment variables is convenient for dynamic insertion of OS-related stuff (such as current user name, home directory and other user-specific directories, content of the PATH environment variable), or values of user-defined environment variables within scripts and automated systems such as continuous integration/delivery.

Special-case: `.reg` (registry script files) outputs to the required **UTF-16 LE** encoding (all other outputs are **UTF-8**).

**Key features**

* **Placeholders**: `{{ ... }}` with a **namespace** and optional **pipe** filters.
  * General form: `{{ Namespace.<Qualifier> < | Filter1 | Filter2 ... > }}`
  * Filter - general form: `FilterrName<"arg1":"arg2":...>`
    * Examples: `regesc`, `append:"  `nThe text: "`, `replace:"myusername":"MyUserName"`
  * Examples:
    * `{{ env.USERNAME }}`
    * `{{ var.ScriptFilePath | regesc }}`
    * `{{ env.LOCALAPPDATA | pathappend:"Local\Programs\" | regesc }}`
    * `{{ var.MyFilePath | replace:"/":"\" | replace:"\":"\\" }}`
* **Namespaces**:
  * `var.<Name>` - user-provided variables (via `-Variables @{ ... }` or `-Variable Name Value`).
  * `env.<NAME>` - environment variables (e.g., `env.USERNAME`, `env.LOCALAPPDATA`). Note that on Linux, environment variable names are case sensitive.
  * *(Reserved for future)* `ps:` – evaluate PowerShell expressions (not implemented yet).
* **Filters** (chainable):
  * `regq` - escapes quotes (replaces `"` => `\"`); used e.g. for .reg (Windows Registry script) files
  * `regesc` - escapes quotes and backslashes (replaces `\` => `\\` and `"` => `\"`); used for .reg (Windows Registry script) files and others
  *  `pathappend:"\tail"` - appends paths with whatever follows the colon
  *  `pathquote` - encloses path in quotes, if not already enclosed
  * `pathwinabs` - converts a path to canonical Windows-style absolute path (also converts slashes to backslashes, replaces `\.\` and duplicate backslashes, resolves `..\`)
  * `pathlinuxabs` - converts a path to canonical Linux-style absolute path (converts backslashes to slashes, replaces `/./` and duplicate slashes, resolves `../`, maps drive letters (C:\ → /c/) if path starts with them)
  * `pathosabs` - converts a path to canonical absolute path for the current operating system (OS); if the current OS is Windows, the result is equivalent to `pathwinabs`, otherwise it is equivalent to `pathlinuxabs`.
  * `pathwin` - converts a path to canonical Windows-style path while preserving relative paths (converts slashes to backslashes, replaces `\.\` and duplicate backslashes, etc.)
  * `pathlinux` - converts a path to canonical Linux-style path while preserving relative paths (converts backslashes to slashes, replaces `/./` and duplicate slashes, maps drive letters (C:\ → /c/) if path starts with them)
  * `pathos` - converts a path to canonical path for the current operating system (OS); if the current OS is Windows, the result is equivalent to `pathwin`, otherwise it is equivalent to `pathlinux`.
  *  `lower` - changes input string to lower case
  *  `upper` - changes input string to upper case
  *  `trim` - trims leading and trailing whitespace from the input string
  * `replace:"old":"new"` - replaces all occurrences of string "old" (1st argument) with string "new" (2nd argument)
  * `default:"fallback"` - If the value is null or empty string, then argument of the filter (fallback in this case) is substituted, otherwise the value is kept the same
  * `append:"text"` - appends literal text to the input string
  * `prepend:"text"` - prepends input string with literal text
* **Whitespace tolerant**: placeholders can span multiple lines; spaces/newlines around `|` are ignored.
* **Output path**:

  * `-Output` optional. If omitted, writes next to the template with `.tmpl` removed.

**Parameters**

* `-Template <path>` – template file (`.tmpl` recommended). Relative paths are resolved from the script’s location.
* `-Output <path>` – optional; if omitted, output = template without `.tmpl`.
* One of:

  * `-Variables @{ Name='value'; ... }` – hashtable of variables.
  * or multiple `-Variable Name -Value Value` pairs.

**Examples**

```powershell
# 1) Using env only (no variables)
.\ExpandTemplate.ps1 `
  -Template .\AddCode_Example1.reg.tmpl `
  -Output   .\AddCode_Example1.reg

# 2) Using a hashtable of variables
.\ExpandTemplate.ps1 `
  -Template .\AddCode_Example2.reg.tmpl `
  -Output   .\AddCode_Example2.reg `
  -Variables @{ Title = 'Open with VS Code' }

# 3) Multiple -Variable pairs
.\ExpandTemplate.ps1 `
  -Template .\My.reg.tmpl `
  -Variable Title -Value 'Open with VS Code' `
  -Variable Tool  -Value 'Code.exe'
```

**Placeholder Rules**

```text
{{ var.Title | regq }}
{{ env.USERPROFILE | pathappend:"\AppData\Local\Programs\Microsoft VS Code\Code.exe" | regesc }}
```

* `var.Title` is replaced with the value of `Title`.
* `env.USERPROFILE` pulls from the environment.
* `pathappend` concatenates with correct slashes.
* `regq` quotes/escapes for .reg value strings.

**Filter Argumants**

See [Filter Arguments (external document, to be included here)](./FilterArguments.md)

**Examples & Helpers**

* `AddCode_GenerateRegScriptsFromTemplates.ps1` – example that expands:

  * `AddCode_Example_WithPlaceholders.reg` (a .reg with simple placeholders you can also fill manually),
  * `AddCode_Example1.reg.tmpl`,
  * `AddCode_Example2.reg.tmpl`.

> **Error handling:** if a `var.*` variable is referenced but not provided, or an environment variable is missing, the script prints a descriptive error and exits.


