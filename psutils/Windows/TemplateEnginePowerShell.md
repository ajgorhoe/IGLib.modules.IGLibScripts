
# PowerShell Template Engine

## PowerShell Template Engine (`ExpandTemplate.ps1`)

**Description**
Generates final files from templates (`.tmpl`) by expanding dynamic placeholders. You can mix **user variables**, **environment variables**, and **filters** to transform values as they’re inserted. `.reg` outputs are written as **UTF-16 LE** (others as UTF-8).

**Key features**

* **Placeholders**: `{{ ... }}` with a **namespace** and optional **pipe** filters.
  General form: `{{ Namespace.Qualifier | Filter1[:arg1[:arg2...]] | Filter2 ... }}`.
  Example: `{{ env.LOCALAPPDATA | pathappend:"Microsoft" | regesc }}`.
* **Namespaces**

  * `var.<Name>` — user variables supplied via `-Var`, `-Variables`, or `-VarsFile`.
  * `env.<NAME>` — environment variables (case-sensitive on Linux).
* **Whitespace tolerant** — placeholders can span multiple lines; spaces/newlines around `|` are ignored.

---

## Command-line

~~~powershell
.\ExpandTemplate.ps1 `
  -Template <TemplateFile.tmpl> `
  [-Output <OutputFile>] `
  [-Var <"Name=Value"[,...]>] `
  [-Variables <Hashtable>] `
  [-VarsFile <FileWithVars>] `
  [-Encoding <Encoding>] `
  [-Strict] `
  [-OutVerbose] [-OutDebug] [-OutTrace]
~~~

**Parameters**

* `-Template <path>` – template file (recommended extension: `.tmpl`). If `-Output` is omitted, the script writes next to the template with `.tmpl` removed.
* `-Output <path>` – optional output path. Defaults to template path without `.tmpl`.
* `-Var <array of strings>` – inline `Name=Value` pairs; may be repeated or passed as an array.
* `-Variables <hashtable>` – e.g. `@{ Project='MyProj'; Version='1.2.3' }`.
* `-VarsFile <file>` – file with variables (simple `Name=Value` lines or JSON, as in the reference). Values from `-Var` and `-Variables` override `-VarsFile`.
* `-Encoding <string>` – output encoding (default UTF-8; `.reg` is forced to UTF-16 LE).
* `-Strict` – enable stricter validation (documented in the reference; useful to surface problems early).
* **Output verbosity switches** (new):

  * `-OutVerbose` – high-level progress/log output.
  * `-OutDebug` – more detailed, includes filter-level info (implies verbose).
  * `-OutTrace` – very detailed, step-by-step tracing (implies debug & verbose).

> Note: The script uses **custom switches** `-OutVerbose`, `-OutDebug`, and `-OutTrace` (PowerShell’s common `-Verbose`/`-Debug` are **not** used by this tool).

**Variable precedence**
`VarsFile` < `Variables` < `Var` (later sources override earlier ones).

---

## Placeholders

**Form**

~~~text
{{ head | filter1[:arg1[:arg2...]] | filter2 ... }}
~~~

* **Head**

  * `var.Name` → value from `-Var`, `-Variables`, or `-VarsFile`.
  * `env.NAME` → environment variable.
* **Filters**
  Applied **left to right**; arguments separated by `:`. Arguments may be in **double quotes**, or **unquoted** when they contain no whitespace and none of `: | } {`. In quoted form you can escape `\"` and `\\`. This allows Windows paths to be written cleanly.

**Escaping literal `{{` / `}}` in templates**
Use `\{{` and `\}}`, or `\{\{` and `\}\}` (the second pair is sometimes safer for custom parsers).

**Examples**

~~~text
{{ var.Project }}                    → "MyProj"
{{ env.USERNAME | upper }}           → uppercase username
{{ var.PathWin | pathappend:"bin" }} → append subfolder
~~~

---

## Filters

### String manipulation

* `lower`, `upper`, `trim`, `append:"text"`, `prepend:"text"`, `replace:"old":"new"`, `default:"fallback"`.

### Path handling

* `pathappend:"part"` – append path segment.
* `pathquote` – wrap in quotes if not already.
* `pathwin` / `pathwinabs` – normalize to Windows path (absolute with `pathwinabs`).
* `pathlinux` / `pathlinuxabs` – normalize to Linux path (absolute with `pathlinuxabs`; handles drive letter mapping such as `C:\ → /c/`).
* `pathos` / `pathosabs` – normalize to current OS style (relative/absolute).

**Illustration (from samples):**

~~~text
{{ var.PathWin | pathappend:"dir1\dir2\icon.png" | replace:"\\":"/" }}
→ "C:/Program Files (x86)/Microsoft SQL Server/dir1/dir2/icon.png"
~~~

### Escaping / encoding / decoding

> The older short manual used `urlenc`/`urldec` and `xmlenc`/`xmldec`; the **correct names are** `urlencode`/`urldecode` and `xmlencode`/`xmldecode`.

* **URL**: `urlencode` / `urldecode`
  Example round-trip shown in the sample outputs.
* **XML/HTML**: `xmlencode` / `xmldecode`
  Example round-trip shown in the sample outputs.
* **C / Java / C# escapes**:
  `escc` / `fromescc`, `escjava` / `fromescjava`, `esccs` / `fromesccs`. (Used extensively in the samples to prove round-trips.)
* **Base64 / Hex**:
  `base64` / `frombase64`, `hex` / `fromhex`, plus string helpers `strfrombase64`, `strfromhex` for direct string recovery. Type behavior (e.g., `frombase64` → `Byte[]`) is demonstrated in the examples.

### Compression

* `gzip` / `gunzip` – compress/decompress.
  Pipe through text conversions where needed:

  * `... | gzip | base64` → text; `... | frombase64 | gunzip` → back to bytes.
  * To get a **string** after `gunzip`, use `... | gunzip | utf16` **or** `... | gunzip:"utf16"` or `strgunzip`. (UTF-8 variant for `gunzip:"utf8"` is intentionally **not** implemented.)

---

## Unquoted filter arguments

Arguments **don’t need quotes** if they contain only letters/digits/underscores and none of the disallowed characters; quoted form remains valid and required when spaces/special characters are present. Examples in the docs and sample show both styles.

---

## Multi-line & spacing tolerance

Placeholders can include spaces and span multiple lines; token spacing around `|` and `:` is flexible (see examples block in the template).

---

## Examples

**Minimal:**

~~~powershell
# Using only env vars (no user variables)
.\ExpandTemplate.ps1 `
  -Template .\AddCode_Example1.reg.tmpl `
  -Output   .\AddCode_Example1.reg
~~~



**With variables (hashtable):**

~~~powershell
.\ExpandTemplate.ps1 `
  -Template .\AddCode_Example2.reg.tmpl `
  -Output   .\AddCode_Example2.reg `
  -Variables @{ Title = 'Open with VS Code' }
~~~



**Inline variables & tracing:**

~~~powershell
.\ExpandTemplate.ps1 `
  -Template .\TemplateExample.txt.tmpl `
  -Output   .\TemplateExample.txt `
  -Var @(
    "MyVarSimple=$MyVarSimple", "MyVarLong=$MyVarLong",
    "PathWin=$PathWin", "PathUnix=$PathUnix",
    "DirtyRelativePath=$DirtyRelativePath", "DirtyAbsolutePath=$DirtyAbsolutePath",
    "EscapedStr=$EscapedStr", "EscapedStrSimple=$EscapedStrSimple",
    "ForUrlEncoding=$ForUrlEncoding", "ForXMLEncoding=$ForXMLEncoding"
  ) `
  -OutTrace    # implies -OutDebug and -OutVerbose
~~~

**Template snippets covered by the sample set include escaping braces, path normalization, and encoding/decoding round-trips.**

---

## Error handling (summary)

* Unknown filters → descriptive error.
* Unclosed placeholders → error with position.
* Variables not found → (behavior depends on context; use `-Strict` when you want hard failures).

---

## Extending with custom filters (advanced)

Filters are implemented in the script (see `Apply-Filters`). To add your own, locate the switch over filter names and add a clause like:

~~~powershell
'reverse' { $val = -join ($val.ToCharArray() | [Array]::Reverse()); continue }
~~~

Then use `{{ var.Name | reverse }}` in templates.

---

## Notes & best practices

* Prefer quoted filter arguments unless you’re sure unquoted is safe.
* Keep templates in version control; generated files should usually be ignored. (Example set includes the expected output for verification.)
* For `.reg` files, remember output encoding is UTF-16 LE.

