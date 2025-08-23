<#
.SYNOPSIS
  Expand a text template file by replacing placeholders with user variables and/or environment variables.

.DESCRIPTION
  ExpandTemplate.ps1 reads a template file, finds placeholders of the form:

      {{ var.Name | filter[:"arg"] | filter[:"arg"] ... }}
      {{ env.NAME  | filter[:"arg"] | filter[:"arg"] ... }}

  …and replaces them with concrete values. Two namespaces are supported:

    • var.*   — values supplied by the caller via -Variables, -Var, or -VarsFile
    • env.*   — environment variables (Process → User → Machine lookup)

  Filters (applied left-to-right):

    • trim        — String.Trim()
    • upper       — Uppercase
    • lower       — Lowercase
    • regq        — Escape " as \" (e.g. for .reg REG_SZ lines)
    • regesc      — Escape " as \" and \ as \\ (e.g. for paths in .reg REG_SZ lines)
    • quote       — Wrap the whole value in double quotes
    • pathquote   — Quote the value like a path if not already quoted
    • append:"x"  — Append literal text x
    • prepend:"x" — Prepend literal text x
    • replace:"old":"new" — Literal string replacement (no regex)
    • default:"fallback" — Use fallback only if value is empty/whitespace
    • pathappend:"\suffix" — Append a path suffix verbatim (no separator logic)
    • addarg:"%1" — Append a space + quoted argument (e.g., " "%1" or " "%V"")
    • expandsz    — Encode the current string as REG_EXPAND_SZ in .reg syntax:
                     hex(2):<UTF-16LE BYTES WITH NUL TERMINATOR>

  Whitespace/newlines around pipes are tolerated, so multi-line placeholders work:
      {{ 
         env.USERPROFILE
         | pathappend:"\App"
         | pathappend:"\Bin"
         | regq
      }}

.PARAMETER Template
  Path to the template (.tmpl recommended). Relative paths are resolved from the script location.

.PARAMETER Output
  Optional output path. If omitted, writes next to the template with ".tmpl" removed.
  Files with extension ".reg" are written as UTF-16 LE (Unicode), others as UTF-8.

.PARAMETER Variables
  Hashtable of variables, e.g. -Variables @{ Title='Open with VS Code'; Tool='Code.exe' }

.PARAMETER Variable / Value
  Zero or more pairs, e.g. -Variable Title -Value 'Open with VS Code'

.EXAMPLE
  # Using environment variables only
  .\ExpandTemplate.ps1 `
    -Template .\AddCode_Example1.reg.tmpl `
    -Output   .\AddCode_Example1.reg

.EXAMPLE
  # Using a hashtable of variables
  .\ExpandTemplate.ps1 `
    -Template .\AddCode_Example2.reg.tmpl `
    -Output   .\AddCode_Example2.reg `
    -Variables @{ Title='Open with VS Code' }

.EXAMPLE
  # Supply variables via Name=Value pairs
  .\ExpandTemplate.ps1 `
    -Template .\AddCode_Example.reg.tmpl `
    -Var 'Title=Open with VS Code'

.NOTES
  • To render literal “{{ … }}”, escape braces like:
      \{\{ … \}\}
    (or split the braces across lines). A raw-block feature can be added later.
  • For .reg REG_SZ lines, sometimes you need to escape quotes (filter: regq).
    Backslashes do NOT need doubling in .reg files. But when backslashes
    also need escaping, use the regesc filter, e.g.:
      {{ env.USERPROFILE | pathappend:"\AppData\Local\Programs\Microsoft VS Code\Code.exe" | regesc }}
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Template,

    [Parameter()]
    [string]$Output,

    # Hashtable of variables
    [hashtable]$Variables,

    # Alternate: -Variable Name -Value Value (repeatable)
    [Parameter()]
    [string]$Variable,

    [Parameter()]
    [string]$Value,

    # Allow multiple -Variable/-Value pairs
    [Parameter(ValueFromRemainingArguments)]
    [string[]]$Var
)

# ========================= Resolve paths ========================

# If Template/Output are relative, resolve from the script directory
$ScriptDir = Split-Path -LiteralPath $PSCommandPath -Parent
if (-not (Test-Path -LiteralPath $Template)) {
    $cand = Join-Path $ScriptDir $Template
    if (Test-Path -LiteralPath $cand) { $Template = $cand }
}
if (-not $Output) {
    if ($Template.ToLowerInvariant().EndsWith('.tmpl')) {
        $Output = $Template.Substring(0, $Template.Length - 5)
    } else {
        $Output = "${Template}.out"
    }
} elseif (-not (Split-Path -IsAbsolute $Output)) {
    $Output = Join-Path $ScriptDir $Output
}

if (-not (Test-Path -LiteralPath $Template)) {
    Write-Error "Template not found: ${Template}"
    exit 1
}

# ========================= Build variable table ========================

$VARS = @{}
if ($Variables) {
    foreach ($k in $Variables.Keys) { $VARS[$k] = [string]$Variables[$k] }
}

# Support -Var 'Name=Value' pairs
if ($Var) {
    foreach ($pair in $Var) {
        if ($pair -notmatch '^\s*(?<n>[^=]+)\s*=\s*(?<v>.*)$') {
            Write-Error "Invalid -Var entry: '${pair}'. Use Name=Value."
            exit 1
        }
        $VARS[$Matches['n']] = [string]$Matches['v']
    }
}

# Single -Variable/-Value pair
if ($PSBoundParameters.ContainsKey('Variable')) {
    $VARS[$Variable] = [string]$Value
}

# ========================= Read template ========================

$templateText = Get-Content -LiteralPath $Template -Raw

# ========================= Placeholder engine ========================

# Find all occurrences of {{ ... }} allowing newlines inside.
# We will walk the text and build a result with replacements.
$pattern = '\{\{([\s\S]*?)\}\}'

# ---------------------------------------------------------------------------
# Helper: Apply-Filters
# ---------------------------------------------------------------------------
function Apply-Filters {
    <#
    .SYNOPSIS
      Apply template filters (regq, regesc, quote, pathappend, expandsz, replace, prepend, default, pathquote, etc.) to a value.

    .PARAMETER Value
      Initial string value.

    .PARAMETER Pipeline
      Array of @{ name='filter'; arg='firstArg'; args = @('a','b',...) } entries.

    .OUTPUTS
      [string] Transformed value.
    #>
    param(
        [string]   $Value,
        [object[]] $Pipeline
    )

    foreach ($f in $Pipeline) {
        $name = $f.name.ToLowerInvariant()
        $arg  = $f.arg
        $args = $f.args

        switch ($name) {
            'trim'       { $Value = $Value.Trim() }
            'upper'      { $Value = $Value.ToUpper() }
            'lower'      { $Value = $Value.ToLower() }
            'regq'       { $Value = $Value.Replace('"','\"') }
            'regesc'     { $Value = $Value.Replace('\','\\').Replace('"','\"') }
            'quote'      { $Value = '"' + $Value + '"' }
            'pathquote'  { if ($Value -notmatch '^\s*\".*\"\s*$') { $Value = '"' + $Value + '"' } }
            'prepend'    { $Value = ($(if ($null -ne $arg) { $arg } else { '' })) + $Value }
            'append'     { $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) }
            'replace'    {
                if ($args.Count -lt 2) { throw "replace filter requires two arguments: replace:\"old\":\"new\"" }
                $old = $args[0]; $new = $args[1]
                $Value = $Value.Replace($old, $new)
            }
            'default'    {
                if ([string]::IsNullOrWhiteSpace($Value)) { $Value = ($(if ($null -ne $arg) { $arg } else { '' })) }
            }
            'pathappend' { $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) }
            'addarg'     { $Value = $Value + ' "' + ($(if ($null -ne $arg) { $arg } else { '' })) + '"' }

            'expandsz' {
                # Encode as REG_EXPAND_SZ in .reg hex(2) form (UTF-16LE, null-terminated)
                $bytes = [System.Text.Encoding]::Unicode.GetBytes($Value + [char]0)
                $hex   = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ','
                $Value = 'hex(2):' + $hex
            }

            default     { throw "Unknown filter '${name}'." }
        }
    }
    return $Value
}

# ---------------------------------------------------------------------------
# Helper: Parse-Placeholder
# Parses the inside of {{ ... }} into namespace, name, and filter pipeline.
# Expects "var.Name" or "env.NAME" followed by optional "| filter[: "arg"]".
# Now supports multiple args per filter: filter:"a":"b"
# ---------------------------------------------------------------------------
function Parse-Placeholder {
    <#
    .SYNOPSIS
      Parse a placeholder expression into its parts.

    .PARAMETER ExprText
      The raw text inside {{ and }}.

    .OUTPUTS
      Hashtable with keys: ns, name, filters (array of @{name;arg;args}).
    #>
    param([string]$ExprText)

    # Allow expressions to contain newlines and arbitrary whitespace.
    # We'll split on '|' and trim each segment afterwards.
    $parts = $ExprText -split '\|'
    if ($parts.Count -lt 1) { throw "Empty expression in placeholder." }

    $head = $parts[0].Trim()
    if ($head -notmatch '^(?<ns>var|env)\.(?<name>[A-Za-z_][A-Za-z0-9_\.]*)$') {
        throw "Invalid placeholder head '${head}'. Use 'var.Name' or 'env.NAME'."
    }
    $ns   = $Matches['ns']
    $name = $Matches['name']

    $filters = @()
    for ($i=1; $i -lt $parts.Count; $i++) {
        $seg = $parts[$i].Trim()
        if (-not $seg) { continue }

        # Expect: name [ : "arg" ] [ : "arg" ] ...
        if ($seg -notmatch '^(?<fn>[A-Za-z_][A-Za-z0-9_]*)') {
            throw "Invalid filter segment '${seg}'. Use filter or filter:""arg"" (multiple args allowed)."
        }
        $fname = $Matches['fn']
        $rest  = $seg.Substring($Matches[0].Length)

        $args = @()
        while ($rest -match '^\s*:\s*"(?:[^"\\]|\\.)*"') {
            if ($rest -match '^\s*:\s*"(?<arg>(?:[^"\\]|\\.)*)"') {
                $capt = $Matches['arg']
                # unescape \" -> " and \\ -> \
                $capt = $capt -replace '\\"','"' -replace '\\\\','\'
                $args += $capt
                $rest = $rest.Substring($Matches[0].Length)
            } else {
                break
            }
        }

        # Validate there's nothing left but whitespace
        if ($rest.Trim()) {
            throw "Invalid filter segment '${seg}'. Unexpected text after arguments."
        }

        $filters += @{ name = $fname; arg = ($(if ($args.Count -gt 0) { $args[0] } else { $null })); args = $args }
    }

    return @{ ns = $ns; name = $name; filters = $filters }
}

# ---------------------------------------------------------------------------
# Helper: Get-InitialValue
# Resolves the initial value of a placeholder from var.* or env.*.
# Missing values cause an error and the script aborts.
# ---------------------------------------------------------------------------
function Get-InitialValue {
    <#
    .SYNOPSIS
      Resolve the base value for a placeholder (var.* or env.*).

    .PARAMETER Vars
      Hashtable of user variables.

    .PARAMETER Ns
      'var' or 'env'.

    .PARAMETER Name
      Variable or environment variable name.

    .PARAMETER Strict
      Reserved for future use (currently not used).
    #>
    param(
        [hashtable]$Vars,
        [string]$Ns,
        [string]$Name,
        [switch]$Strict
    )

    switch ($Ns) {
        'var' {
            if (-not $Vars.ContainsKey($Name)) {
                throw "Variable '${Name}' was referenced but not provided."
            }
            return [string]$Vars[$Name]
        }
        'env' {
            $v = [System.Environment]::GetEnvironmentVariable($Name, 'Process')
            if (-not $v) { $v = [System.Environment]::GetEnvironmentVariable($Name, 'User') }
            if (-not $v) { $v = [System.Environment]::GetEnvironmentVariable($Name, 'Machine') }
            if (-not $v) {
                throw "Environment variable '${Name}' is not defined."
            }
            return [string]$v
        }
        default { throw "Unknown namespace '${Ns}'." }
    }
}

# ========================= Expand ========================

$errors = New-Object System.Collections.Generic.List[string]

$expanded = [System.Text.RegularExpressions.Regex]::Replace(
    $templateText,
    $pattern,
    {
        param($m)
        $expr = $m.Groups[1].Value

        # Ignore escaped '{{' written as '\{{'
        if ($expr.StartsWith('\')) {
            return '{{' + $expr.Substring(1) + '}}'
        }

        try {
            $ph = Parse-Placeholder $expr
            $val0 = Get-InitialValue -Vars $VARS -Ns $ph.ns -Name $ph.name -Strict:$Strict
            Write-Host "  Unfiltered value:`n  $val0"
            $out  = Apply-Filters -Value $val0 -Pipeline $ph.filters
            Write-Host "  Final value:`n  $out"
            return $out
        } catch {
            $errors.Add("Error in placeholder '{{ ${expr} }}': $($_.Exception.Message)")
            return "<ERROR:$expr>"
        }
    }
)

if ($errors.Count -gt 0) {
    $nl = [Environment]::NewLine
    Write-Error ("Template expansion failed:{0}{1}" -f $nl, ($errors -join $nl))
    exit 1
}

# ========================= Write output ========================

$ext = [System.IO.Path]::GetExtension($Output).ToLowerInvariant()
$encoding = if ($ext -eq '.reg') { 'Unicode' } else { 'UTF8' }

Set-Content -LiteralPath $Output -Value $expanded -Encoding $encoding
Write-Host "`nTemplate expanded to:`n  ${Output}`n    (encoding: ${encoding})"

Write-Host "`n  ... template expansion completed.`n" -ForegroundColor Green
