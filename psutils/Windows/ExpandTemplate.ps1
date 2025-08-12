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
    • regq        — Escape " as \" for .reg REG_SZ lines
    • quote       — Wrap the whole value in double quotes
    • append:"x"  — Append literal text x
    • pathappend:"\suffix" — Append a path suffix verbatim (no separator logic)
    • addarg:"%1" — Append a space + quoted argument (e.g., `" "%1"` or `" "%V"`)
    • expandsz    — Encode the current string as REG_EXPAND_SZ in .reg syntax:
                     hex(2):aa,bb,... (UTF-16LE bytes with terminating 00 00)

  Undefined variables and environment variables:
    If a placeholder references an unknown var/env, the script prints an
    informative error and aborts (non-zero exit code), as requested.

  Paths:
    -Template and -Output accept absolute or relative paths.
    Relative paths are resolved first against the script folder ($PSScriptRoot),
    then against the current working directory. If -Output is omitted, the
    output file is created next to the template by stripping one of:
      .tmpl | .template | .tpl | .in
    (If no known suffix is found, ".out" is appended.)

  Encoding:
    Output is written as UTF-16LE (Unicode) to suit .reg files.

.PARAMETER Template
  Path to the template file (*.tmpl recommended). Absolute or relative.

.PARAMETER Output
  Path for the expanded output file. If omitted, derived from -Template:
  same folder, without the .tmpl/.template/.tpl/.in suffix (or “.out” appended).

.PARAMETER Variables
  Hashtable of user variables, e.g.:
      -Variables @{ Title='Open with VS Code'; App='Code.exe' }

.PARAMETER Var
  Zero or more Name=Value pairs, e.g.:
      -Var 'Title=Open with VS Code' 'KeyName=Open_with_VS_Code'

  These overlay/override entries from -Variables and -VarsFile.

.PARAMETER VarsFile
  JSON (.json) or PowerShell data (.psd1) file containing variables.
  Example JSON: { "Title": "Open with VS Code" }

.PARAMETER Strict
  Reserved for future expansion. Missing variables already cause the script to
  fail with a clear error (current behavior matches your requirement).

.EXAMPLE
  # Simple expansion using only env placeholders in the template
  .\ExpandTemplate.ps1 -Template .\AddCode_Example.reg.tmpl

.EXAMPLE
  # Supply a custom title via hashtable, and choose output path
  .\ExpandTemplate.ps1 `
    -Template .\AddCode_Example.reg.tmpl `
    -Output   .\AddCode_Example.reg `
    -Variables @{ Title = 'Open with VS Code' }

.EXAMPLE
  # Supply variables via Name=Value pairs
  .\ExpandTemplate.ps1 `
    -Template .\AddCode_Example.reg.tmpl `
    -Var 'Title=Open with VS Code'

.NOTES
  • To render literal “{{ … }}” in the template, escape braces like:
      \{\{ … \}\}
    (or split the braces across lines). A raw-block feature can be added later.
  • For .reg REG_SZ lines you usually only need to escape quotes (filter: regq).
    Backslashes do NOT need doubling in .reg files.
#>

param(
    [Parameter(Mandatory)] [string] $Template,
    [string] $Output,
    [hashtable] $Variables,
    [string[]] $Var,
    [string] $VarsFile,
    [switch] $Strict
)

# ---------------------------------------------------------------------------
# Helper: Resolve-PathSmart
# Resolves a path. If relative, tries relative to script folder, then CWD.
# Throws if not found (for -Template); for -Output we only resolve when provided.
# ---------------------------------------------------------------------------
function Resolve-PathSmart {
    <#
    .SYNOPSIS
      Resolve a path relative to script folder or current directory.

    .PARAMETER Path
      The path to resolve (absolute or relative).

    .OUTPUTS
      [string] Fully-qualified path.

    .NOTES
      Uses -LiteralPath to avoid wildcard expansion.
    #>
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    $candidates = @(
        (Join-Path $PSScriptRoot $Path),
        (Join-Path (Get-Location) $Path)
    )
    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    throw "Template/output path not found: ${Path}"
}

# ---------------------------------------------------------------------------
# Helper: ConvertTo-Hashtable
# Converts PSCustomObject/arrays from ConvertFrom-Json into plain hashtables.
# ---------------------------------------------------------------------------
function ConvertTo-Hashtable {
    <#
    .SYNOPSIS
      Convert an object tree (e.g., from JSON) into hashtables/arrays.

    .PARAMETER Object
      Input object (PSCustomObject, array, hashtable, or scalar).

    .OUTPUTS
      Hashtables/arrays/scalars mirroring the input structure.
    #>
    param($Object)

    if ($Object -is [hashtable]) { return $Object }
    if ($null -eq $Object) { return @{} }
    if ($Object -is [System.Collections.IEnumerable] -and -not ($Object -is [string])) {
        $arr = @()
        foreach ($item in $Object) { $arr += (ConvertTo-Hashtable $item) }
        return $arr
    }
    if ($Object.PSObject -and $Object.PSObject.Properties) {
        $ht = @{}
        foreach ($p in $Object.PSObject.Properties) {
            $ht[$p.Name] = ConvertTo-Hashtable $p.Value
        }
        return $ht
    }
    return $Object
}

# ---------------------------------------------------------------------------
# Helper: Load-VarsFile
# Loads a JSON (.json) or PowerShell data (.psd1) file into a hashtable.
# ---------------------------------------------------------------------------
function Load-VarsFile {
    <#
    .SYNOPSIS
      Load variables from a JSON or PSD1 file.

    .PARAMETER Path
      Path to the file (.json or .psd1). Resolved via Resolve-PathSmart.

    .OUTPUTS
      [hashtable] Variables dictionary.
    #>
    param([string]$Path)

    if (-not $Path) { return @{} }
    $full = Resolve-PathSmart $Path
    $ext  = [System.IO.Path]::GetExtension($full).ToLowerInvariant()

    switch ($ext) {
        '.json' {
            try {
                $raw = Get-Content -LiteralPath $full -Raw
                $obj = $raw | ConvertFrom-Json
                return ConvertTo-Hashtable $obj
            } catch {
                throw "Failed to parse JSON vars file '${full}': $($_.Exception.Message)"
            }
        }
        '.psd1' {
            try {
                return Import-PowerShellDataFile -LiteralPath $full
            } catch {
                throw "Failed to parse PSD1 vars file '${full}': $($_.Exception.Message)"
            }
        }
        default {
            throw "Unsupported vars file extension '${ext}'. Use .json or .psd1."
        }
    }
}

# ---------------------------------------------------------------------------
# Helper: Merge-Variables
# Shallow merge of two hashtables (Overlay overrides Base).
# ---------------------------------------------------------------------------
function Merge-Variables {
    <#
    .SYNOPSIS
      Merge two variable sets (overlay overrides base).

    .PARAMETER Base
      Base hashtable.

    .PARAMETER Overlay
      Overlay hashtable whose keys override Base.

    .OUTPUTS
      [hashtable] Merged dictionary.
    #>
    param([hashtable]$Base, [hashtable]$Overlay)

    $dest = @{}
    if ($Base)    { foreach ($k in $Base.Keys)    { $dest[$k] = $Base[$k] } }
    if ($Overlay) { foreach ($k in $Overlay.Keys) { $dest[$k] = $Overlay[$k] } }
    return $dest
}

# ---------------------------------------------------------------------------
# Helper: Parse-VarPairs
# Parse -Var entries like 'Name=Value' into a hashtable.
# ---------------------------------------------------------------------------
function Parse-VarPairs {
    <#
    .SYNOPSIS
      Parse Name=Value pairs into a hashtable.

    .PARAMETER Pairs
      Array of strings in the form Name=Value.

    .OUTPUTS
      [hashtable] Variables dictionary.
    #>
    param([string[]]$Pairs)

    $ht = @{}
    foreach ($p in ($Pairs | Where-Object { $_ -ne $null })) {
        if ($p -notmatch '^\s*([^=]+)\s*=\s*(.*)\s*$') {
            throw "Invalid -Var entry '${p}'. Use Name=Value."
        }
        $name = $Matches[1].Trim()
        $val  = $Matches[2]
        $ht[$name] = $val
    }
    return $ht
}

# ---------------------------------------------------------------------------
# Helper: Apply-Filters
# Applies a pipeline of filters to a string, returning the transformed value.
# ---------------------------------------------------------------------------
function Apply-Filters {
    <#
    .SYNOPSIS
      Apply template filters (regq, quote, pathappend, expandsz, etc.) to a value.

    .PARAMETER Value
      Initial string value.

    .PARAMETER Pipeline
      Array of @{ name='filter'; arg='optional' } entries.

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

        switch ($name) {
            'trim'       { $Value = $Value.Trim() }
            'upper'      { $Value = $Value.ToUpper() }
            'lower'      { $Value = $Value.ToLower() }
            'regq'       { $Value = $Value -replace '"', '\"' }
            'quote'      { $Value = '"' + $Value + '"' }
            'append'     { $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) }
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
# ---------------------------------------------------------------------------
function Parse-Placeholder {
    <#
    .SYNOPSIS
      Parse a placeholder expression into its parts.

    .PARAMETER ExprText
      The raw text inside {{ and }}.

    .OUTPUTS
      Hashtable with keys: ns, name, filters (array of @{name;arg}).
    #>
    param([string]$ExprText)

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

        $fname = $seg
        $farg  = $null

        # filter:"arg"  (arg may contain \" escapes)
        if ($seg -match '^(?<fn>[A-Za-z_][A-Za-z0-9_]*)\s*:\s*"(?<arg>(?:[^"\\]|\\.)*)"\s*$') {
            $fname = $Matches['fn']
            $farg  = $Matches['arg'] -replace '\\\"','"'
        } elseif ($seg -match '^(?<fn>[A-Za-z_][A-Za-z0-9_]*)\s*$') {
            $fname = $Matches['fn']
            $farg  = $null
        } else {
            throw "Invalid filter segment '${seg}'. Use filter or filter:""arg""."
        }
        $filters += @{ name = $fname; arg = $farg }
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
      Reserved for future use (current behavior always errors on missing values).

    .OUTPUTS
      [string] The resolved value.
    #>
    param([hashtable]$Vars, [string]$Ns, [string]$Name, [switch]$Strict)

    switch ($Ns) {
        'var' {
            if (-not $Vars.ContainsKey($Name)) {
                $msg = "Undefined user variable '${Name}' ({{ var.${Name} }})."
                throw $msg
            }
            return [string]$Vars[$Name]
        }
        'env' {
            $val = [System.Environment]::GetEnvironmentVariable($Name, 'Process')
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($Name, 'User') }
            if (-not $val) { $val = [System.Environment]::GetEnvironmentVariable($Name, 'Machine') }
            if (-not $val) {
                $msg = "Environment variable '${Name}' not defined ({{ env.${Name} }})."
                throw $msg
            }
            return [string]$val
        }
    }
}

# ========================= Load inputs =========================

$tplPath = Resolve-PathSmart $Template
$tplText = Get-Content -LiteralPath $tplPath -Raw

# Compose variables with precedence: VarsFile < Variables < Var
$varsFromFile = Load-VarsFile $VarsFile
$varsMerged   = Merge-Variables $varsFromFile $Variables
$varsCli      = Parse-VarPairs $Var
$VARS         = Merge-Variables $varsMerged $varsCli

# Compute default output if omitted
if (-not $Output) {
    $dir  = [System.IO.Path]::GetDirectoryName($tplPath)
    $fn   = [System.IO.Path]::GetFileName($tplPath)
    $base = $fn
    foreach ($suffix in @('.tmpl','.template','.tpl','.in')) {
        if ($base.ToLower().EndsWith($suffix)) {
            $base = $base.Substring(0, $base.Length - $suffix.Length)
            break
        }
    }
    if ($base -eq $fn) { $base = $fn + '.out' }
    $Output = Join-Path $dir $base
} else {
    if (-not [System.IO.Path]::IsPathRooted($Output)) {
        $Output = Join-Path $PSScriptRoot $Output
    }
}

# ========================= Expand template =====================

$pattern = '\{\{\s*(.+?)\s*\}\}'
$errors  = New-Object System.Collections.Generic.List[string]

$expanded = [System.Text.RegularExpressions.Regex]::Replace(
    $tplText,
    $pattern,
    {
        param($m)
        $expr = $m.Groups[1].Value
        try {
            $ph   = Parse-Placeholder $expr
            $val0 = Get-InitialValue -Vars $VARS -Ns $ph.ns -Name $ph.name -Strict:$Strict
            $out  = Apply-Filters -Value $val0 -Pipeline $ph.filters
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

# Write as UTF-16LE (Unicode) — ideal for .reg files
Set-Content -LiteralPath $Output -Value $expanded -Encoding Unicode
Write-Host "Template expanded to: ${Output}"
