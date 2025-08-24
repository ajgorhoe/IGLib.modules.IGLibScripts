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

    • trim           - String.Trim()
    • upper          - Uppercase
    • lower          - Lowercase
    • regq           - Escape " as \" (e.g. for .reg REG_SZ lines)
    • regesc         - Escape " as \" and \ as \\ (e.g. for paths in .reg REG_SZ lines)
    • quote          - Wrap the whole value in double quotes
    • append:"text"  - Append literal text x
    • prepend:"text" - Prepend literal text
    • pathappend:"\suffix" — Append a path suffix verbatim (no separator logic)
    • replace:"old":"new" - Replace all occurrences of old with new
    • default:"fallback"  - Use fallback if the current value is empty
    • pathquote      - Wrap in quotes if not already quoted
    • addarg:"%1"    - Append a space + quoted argument (e.g., `" "%1"` or `" "%V"`)
    • expandsz       - Encode the current string as REG_EXPAND_SZ in .reg syntax:
                       hex(2):aa,bb,... (UTF-16LE bytes with terminating 00 00)

  Multi-line placeholders:
    Placeholders can span multiple lines and contain pipes on separate lines. Whitespace
    around tokens is ignored. Example:

      {{ 
        env.USERPROFILE |
        pathappend:"\Programs\App\app.exe" | regesc
      }}

  Undefined variables and environment variables:
    If a placeholder references an unknown var/env, the script prints an
    informative error and aborts.

  Paths:
    -Template and -Output accept absolute or relative paths.
    Relative paths are resolved first against the script folder ($PSScriptRoot),
    then against the current working directory. If -Output is omitted, the
    output file is created next to the template by stripping one of:
      .tmpl | .template | .tpl | .in
    (If no known suffix is found, ".out" is appended.)

  Encoding:
    Output encoding depends on the target extension:
      • .reg  → UTF-16LE (Unicode)
      • other → UTF-8

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
  • For .reg REG_SZ lines, sometimes you need to escape quotes (filter: regq).
    Backslashes do NOT need doubling in .reg files. But when backslashes
    also need escaping, use the regesc filter, e.g.:
      {{ env.USERPROFILE | pathappend:"\App\app.exe" | regesc }}
#>

param(
    [Parameter(Mandatory)] [string] $Template,
    [string] $Output,
    [hashtable] $Variables,
    [string[]] $Var,
    [string] $VarsFile,
    [switch] $Strict
)

function Write-HashTable {
    param(
        [hashtable]$Table
    )
    if ($null -eq $Table) {
        Write-Host "  NULL hashtable"
        return
    }
    if ($Table.Count -eq 0) {
        Write-Host "  EMPTY hashtable"
        return
    }
    foreach ($key in $Table.Keys) {
        Write-Host "  ${key}: $($Table[$key])"
    }
}

function Write-Array {
    param(
        [object[]]$Array
    )
    if ($null -eq $Array) {
        Write-Host "  NULL"
        return
    }
    if ($Array.Count -eq 0) {
        Write-Host "  EMPTY"
        return
    }
    for ($i = 0; $i -lt $Array.Count; $i++) {
        Write-Host "  ${i}: $($Array[$i])"
    }
}


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
      # --- BEGIN minimal patch: normalize access for hashtable/PSCustomObject ---
      # Read the filter name, first-arg, and full-args in a way that works for hashtables too.
      $__isHash = ($f -is [hashtable])

      # Name
      $name = if ($__isHash) { [string]$f['name'] } else { [string]$f.name }

      # First arg (compat with older single-arg code)
      $arg  = if ($__isHash) { $f['arg'] } else { $f.arg }

      # Full args array
      $__args = @()
      if ($__isHash) {
          if ($f.ContainsKey('args') -and $f['args']) {
              $__args = @($f['args'])   # make sure it's an array
          } elseif ($null -ne $arg) {
              $__args = @($arg)
          }
      } else {
          if ($f.PSObject.Properties['args'] -and $f.args) {
              $__args = $f.args
          } elseif ($null -ne $arg) {
              $__args = @($arg)
          }
      }
      # --- END minimal patch ---

          Write-Host ("    filter: {0}" -f $name)
          Write-Host ("      arg  : {0}" -f $arg)
          Write-Host ("      args : {0}" -f ($__args -join ', '))

        switch ($name) {
            'trim'       { $Value = $Value.Trim() }
            'upper'      { $Value = $Value.ToUpper() }
            'lower'      { $Value = $Value.ToLower() }
            'regq'       { $Value = $Value -replace '"', '\"' }
            'regesc'     { $Value = $Value -replace '\\', '\\' -replace '"', '\"' }
            'quote'      { $Value = '"' + $Value + '"' }
            'append'     { $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) }
            'prepend'    {
                $Value = ($(if ($null -ne $f.arg) { $f.arg } else { '' })) + $Value
            }
            'pathappend' { $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) }
            'pathquote'  {
                # Quote only if not already quoted (tolerates surrounding whitespace)
                if ($Value -notmatch '^\s*".*"\s*$') { $Value = '"' + $Value + '"' }
            }
            'addarg'     { $Value = $Value + ' "' + ($(if ($null -ne $arg) { $arg } else { '' })) + '"' }
            'default'    {
                if ([string]::IsNullOrWhiteSpace($Value)) {
                    $Value = ($(if ($null -ne $f.arg) { $f.arg } else { '' }))
                }
            }
            'replace' {
                if ($__args.Count -lt 2) {
                    throw 'replace filter requires two arguments: replace:"old":"new"'
                }
                $old = $__args[0]
                $new = $__args[1]
                $Value = $Value.Replace($old, $new)  # literal replacement, not regex
            }
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
      Parse the inside of {{ ... }} into namespace, name, and a filter pipeline.

    .DESCRIPTION
      Expected head forms:
        var.Name
        env.NAME
      Followed by optional filters separated by pipes:
        | filter
        | filter:"arg"
        | filter:"arg1":"arg2"   # multiple args supported (e.g., replace:"old":"new")

      Whitespace/newlines around pipes and colons are tolerated.

    .PARAMETER ExprText
      Raw text inside the {{ and }} delimiters.

    .OUTPUTS
      Hashtable:
        @{ ns = 'var'|'env'
           name = 'Name'
           filters = @(
               @{ name='filterName'; arg='<firstArg-or-$null>'; args=@('<arg1>','<arg2>',...) },
               ...
           )
        }
    #>
    param([string]$ExprText)

    # Split around '|' (pipes). We’ll trim whitespace per segment.
    $parts = $ExprText -split '\|'
    if ($parts.Count -lt 1) { throw "Empty expression in placeholder." }

    # Head: var.Name or env.NAME
    $head = $parts[0].Trim()
    if ($head -notmatch '^(?<ns>var|env)\.(?<name>[A-Za-z_][A-Za-z0-9_\.]*)$') {
        throw "Invalid placeholder head '${head}'. Use 'var.Name' or 'env.NAME'."
    }
    $ns   = $Matches['ns']
    $name = $Matches['name']

    # Filters (zero or more)
    $filters = @()
    for ($i = 1; $i -lt $parts.Count; $i++) {
        $seg = $parts[$i].Trim()
        if (-not $seg) { continue }

        # Extract filter name
        if ($seg -notmatch '^(?<fn>[A-Za-z_][A-Za-z0-9_]*)') {
            throw "Invalid filter segment '${seg}'. Use 'filter' or 'filter:""arg""' (multiple args allowed)."
        }
        $fname = $Matches['fn']
        $rest  = $seg.Substring($Matches[0].Length)

        # Extract one or more quoted args of the form : "arg"
        $fargs = @()
        while ($rest -match '^\s*:\s*"(?:[^"\\]|\\.)*"') {
            # capture the next quoted arg
            if ($rest -match '^\s*:\s*"(?<arg>(?:[^"\\]|\\.)*)"') {
                $capt = $Matches['arg']
                # Unescape \" -> " and \\ -> \
                $capt = $capt -replace '\\\\','\'   # \\  -> \
                $capt = $capt -replace '\\"','"'    # \"  -> "
                $fargs += $capt
                $rest = $rest.Substring($Matches[0].Length)
            } else {
                break
            }
        }

        # No extra junk allowed after arguments
        if ($rest.Trim()) {
            throw "Invalid filter segment '${seg}'. Unexpected text after arguments."
        }

        # Store both first arg (compat) and full args (for multi-arg filters like replace)
        $filters += @{
            name = $fname
            arg  = ($(if ($fargs.Count -gt 0) { $fargs[0] } else { $null }))
            args = $fargs
        }
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

Write-Host "`nExpanding a template file by $($MyInvocation.MyCommand.Name)..." -ForegroundColor Green
Write-Host "`nScript parameters:"
Write-HashTable $PSBoundParameters
Write-Host "  Positional:"
Write-Array $args
Write-Host "Var:"
Write-Array $Var
Write-Host "Variables:"
Write-HashTable $Variables
Write-Host "`nTemplate path: `n  ${tplPath}"
Write-Host ""

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
# NOTE: The regex now matches across lines (multi-line placeholders):
#       [\s\S] means "any char including newlines". The lazy quantifier (.+?) preserved via (.+?) -> ([\s\S]+?)
$pattern = '\{\{\s*([\s\S]+?)\s*\}\}'
$errors  = New-Object System.Collections.Generic.List[string]

$expanded = [System.Text.RegularExpressions.Regex]::Replace(
    $tplText,
    $pattern,
    {
        param($m)
        $expr = $m.Groups[1].Value
        Write-Host "Processing placeholder:`n  {{ $($expr.Trim() -replace '\r?\n', ' ') }}"
        try {
            $ph   = Parse-Placeholder $expr
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