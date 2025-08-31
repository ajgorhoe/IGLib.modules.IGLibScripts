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

# returns true if $v is a byte array
function Is-ByteVector {
    param([object]$v)
    if ($v -is [byte[]]) { return $true }
    if ($v -is [System.Array]) {
        $et = $v.GetType().GetElementType()
        if ($et) { return ($et -eq [byte]) }
        # object[] with byte elements
        if ($v.Length -gt 0 -and $v[0] -is [byte]) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# FILTERS: encode / decode, compression, escape filters
# These functions implement standard encoding, compression and escaping 
# filters, such as base64/frombase64, hex/fromhex, gzip/gunzip,
# urlencode/urldecode, xmlencode/xmldecode, escc/fromescc (C),
# escjava/fromescjava (Java), esccs/fromesccs (C#).
# ---------------------------------------------------------------------------

# ========================= Helpers: string/bytes =========================

function As-String {
    param([Parameter(Mandatory)] [object]$Value)
    if ($Value -is [byte[]]) { return [System.Text.Encoding]::Unicode.GetString($Value) }
    return [string]$Value
}
function As-Bytes {
    param([Parameter(Mandatory)] [object]$Value)
    if ($Value -is [byte[]]) { return $Value }
    $s = [string]$Value
    return [System.Text.Encoding]::Unicode.GetBytes($s)
}

# ========================= Base64 =========================
function Filter-Base64   { param($v) return [System.Convert]::ToBase64String((As-Bytes $v)) }

function Filter-FromBase64 {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)
    try {
        [byte[]]$bytes = [Convert]::FromBase64String($Value)
        Write-Output -NoEnumerate $bytes   # <— critical
    } catch {
        throw "frombase64: invalid Base64 input ($($_.Exception.Message))."
    }
}

# ========================= Hex (lowercase) =========================
function Filter-Hex {
    param($v)
    $bytes = As-Bytes $v
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Filter-FromHex {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)
    $hex = ($Value -replace '\s+', '')
    if ($hex.Length % 2 -ne 0) { throw "fromhex: hex string length must be even." }

    $list = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $hex.Length; $i += 2) {
        try {
            $b = [Convert]::ToByte($hex.Substring($i,2), 16)
        } catch {
            throw "fromhex: invalid hex at position $i."
        }
        [void]$list.Add($b)
    }
    [byte[]]$bytes = $list.ToArray()
    Write-Output -NoEnumerate $bytes       # critical to return byte[] as-is (instead of enumerating bytes, resulting in object[]
}

# ========================= GZip =========================

function Filter-Gzip {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Value)
    $enc   = [Text.Encoding]::Unicode
    $input = $enc.GetBytes($Value)

    $msOut = New-Object System.IO.MemoryStream
    $gz    = New-Object System.IO.Compression.GZipStream($msOut, [IO.Compression.CompressionLevel]::Optimal, $true)
    $gz.Write($input, 0, $input.Length)
    $gz.Dispose()
    [byte[]]$bytes = $msOut.ToArray()
    $msOut.Dispose()
    Write-Output -NoEnumerate $bytes       # critical to return byte[] as-is (instead of enumerating bytes, resulting in object[])
}

function Filter-Gunzip {
    param($v)
    $inBytes = As-Bytes $v
    $msIn  = New-Object System.IO.MemoryStream(,$inBytes)
    $gz    = New-Object System.IO.Compression.GzipStream($msIn, [System.IO.Compression.CompressionMode]::Decompress)
    $msOut = New-Object System.IO.MemoryStream
    $gz.CopyTo($msOut)
    $gz.Dispose()
    $outBytes = $msOut.ToArray()
    ## Return TEXT (Unicode) by default (old way, not consistent with new 
    ## filters guidelines):
    # return [System.Text.Encoding]::Unicode.GetString($outBytes)
    # Return unzipped value as byte[] (will need utf16 filter to get string):
    Write-Output -NoEnumerate $outBytes   # critical to return byte[] as-is (instead of enumerating bytes, resulting in object[]
}

# ========================= URL encode/decode =========================
function Filter-UrlEncode  { param($v) return [System.Uri]::EscapeDataString((As-String $v)) }
function Filter-UrlDecode  { param($v) return [System.Uri]::UnescapeDataString((As-String $v)) }

# ========================= XML encode/decode =========================
function Filter-XmlEncode {
    param($v)
    $s = As-String $v
    $esc = [System.Security.SecurityElement]::Escape($s)  # &,<,>,"
    return $esc -replace "'", '&apos;'
}
function Filter-XmlDecode {
    param($v)
    $s = As-String $v
    # Basic named entities
    $s = $s -replace '&lt;','<' -replace '&gt;','>' -replace '&quot;','"' -replace '&apos;',"'"
    $s = $s -replace '&amp;','&'
    # Numeric: decimal and hex: &#123; or &#x7B;
    $s = [System.Text.RegularExpressions.Regex]::Replace($s, '&#(\d+);', {
        param($m) [char]([int]$m.Groups[1].Value)
    })
    $s = [System.Text.RegularExpressions.Regex]::Replace($s, '&#x([0-9A-Fa-f]+);', {
        param($m) [char]([Convert]::ToInt32($m.Groups[1].Value,16))
    })
    return $s
}

# ========================= C/C++ style escape/unescape =========================

# Convert string to include C/C++-style escape sequences:
function Escape-C {
    param([string]$s)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        $code = [int]$ch
        switch ($ch) {
            "`t" { [void]$sb.Append('\t'); continue }
            "`n" { [void]$sb.Append('\n'); continue }
            "`r" { [void]$sb.Append('\r'); continue }
            "`b" { [void]$sb.Append('\b'); continue }
            "`f" { [void]$sb.Append('\f'); continue }
            [char]0x0B { [void]$sb.Append('\v'); continue } # vertical tab
            [char]0x07 { [void]$sb.Append('\a'); continue } # bell
            '"'  { [void]$sb.Append('\"'); continue }
            "'"  { [void]$sb.Append("\'"); continue }
            '\'  { [void]$sb.Append("\\"); continue }
        }
        if ($code -lt 0x20 -or $code -eq 0x7F) {
            [void]$sb.Append('\x' + $code.ToString('x2'))
        } else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}

# Convert string from C/C++-style escape sequences (old version, does not handle \x or octal):
function Unescape-C {
    param([string]$s)
    $sb = New-Object System.Text.StringBuilder
    for ($i=0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($c -ne '\') { [void]$sb.Append($c); continue }
        # escape seq
        if ($i + 1 -ge $s.Length) { [void]$sb.Append('\'); break }
        $i++
        switch ($s[$i]) {
            'n' { [void]$sb.Append("`n") }
            'r' { [void]$sb.Append("`r") }
            't' { [void]$sb.Append("`t") }
            'b' { [void]$sb.Append("`b") }
            'f' { [void]$sb.Append("`f") }
            'v' { [void]$sb.Append([char]0x0B) }
            'a' { [void]$sb.Append([char]0x07) }
            '"' { [void]$sb.Append('"') }
            "'" { [void]$sb.Append("'") }
            '\' { [void]$sb.Append('\') }
            'x' {
                # hex (consume up to 2 hex digits)
                $hex = ''
                for ($k=0; $k -lt 2 -and ($i+1) -lt $s.Length -and $s[$i+1] -match '[0-9A-Fa-f]'; $k++) {
                    $i++; $hex += $s[$i]
                }
                if ($hex.Length -gt 0) { [void]$sb.Append([char]([Convert]::ToInt32($hex,16))) }
            }
            default {
                # Octal \ooo (up to 3 digits) or literal
                if ($s[$i] -match '[0-7]') {
                    $oct = $s[$i]
                    for ($k=0; $k -lt 2 -and ($i+1) -lt $s.Length -and $s[$i+1] -match '[0-7]'; $k++) {
                        $i++; $oct += $s[$i]
                    }
                    [void]$sb.Append([char]([Convert]::ToInt32($oct,8)))
                } else {
                    [void]$sb.Append($s[$i])
                }
            }
        }
    }
    return $sb.ToString()
}

# Convert string to include C/C++-style escape sequences:
function Filter-EscC {
    <#
      .SYNOPSIS
        Escapes a string using C/C++-style sequences.

      .NOTES
        - Escapes: \\, \', \", \a, \b, \f, \n, \r, \t, \v, \0
        - Control chars (<0x20 or 0x7F): \xHH (<=0xFF) else \uXXXX/\UXXXXXXXX
        - Surrogate pairs are detected and rendered as \UXXXXXXXX.
    #>
    param([Parameter(Mandatory)][string]$Value)

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Value.Length) {
        $ch = $Value[$i]

        # Surrogate pair handling for full Unicode code points
        if ([char]::IsHighSurrogate($ch) -and $i + 1 -lt $Value.Length -and [char]::IsLowSurrogate($Value[$i+1])) {
            $cp = [char]::ConvertToUtf32($ch, $Value[$i+1])
            [void]$sb.Append('\U')
            [void]$sb.Append(('{0:X8}' -f $cp))
            $i += 2
            continue
        }

        $code = [int][char]$ch
        switch ($code) {
            92 { [void]$sb.Append('\'); [void]$sb.Append('\'); $i++; continue } # \
            34 { [void]$sb.Append('\'); [void]$sb.Append('"'); $i++; continue } # "
            39 { [void]$sb.Append('\'); [void]$sb.Append("'"); $i++; continue } # '

            7  { [void]$sb.Append('\'); [void]$sb.Append('a'); $i++; continue }
            8  { [void]$sb.Append('\'); [void]$sb.Append('b'); $i++; continue }
            12 { [void]$sb.Append('\'); [void]$sb.Append('f'); $i++; continue }
            10 { [void]$sb.Append('\'); [void]$sb.Append('n'); $i++; continue }
            13 { [void]$sb.Append('\'); [void]$sb.Append('r'); $i++; continue }
            9  { [void]$sb.Append('\'); [void]$sb.Append('t'); $i++; continue }
            11 { [void]$sb.Append('\'); [void]$sb.Append('v'); $i++; continue }
            0  { [void]$sb.Append('\'); [void]$sb.Append('0'); $i++; continue }
        }

        if ($code -lt 0x20 -or $code -eq 0x7F) {
            if ($code -le 0xFF) {
                [void]$sb.Append('\x')
                [void]$sb.Append(('{0:X2}' -f $code))
            } else {
                [void]$sb.Append('\u')
                [void]$sb.Append(('{0:X4}' -f $code))
            }
            $i++
            continue
        }

        [void]$sb.Append($ch)
        $i++
    }
    $sb.ToString()
}


# Convert string from C/C++-style escape sequences:
function Filter-FromEscC {
    <#
      .SYNOPSIS
        Decodes C/C++-style escape sequences in a string.

      .NOTES
        Supported: \\, \', \", \?, \a, \b, \f, \n, \r, \t, \v,
                   \0 / \oo / \ooo (octal up to 3 digits),
                   \xH… (1–4 hex digits).
    #>
    param([Parameter(Mandatory)][string]$Value)

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Value.Length) {
        $ch = $Value[$i]
        if ($ch -ne '\') {
            [void]$sb.Append($ch)
            $i++
            continue
        }

        $i++
        if ($i -ge $Value.Length) { [void]$sb.Append('\'); break }
        $esc = $Value[$i]

        switch -CaseSensitive ($esc) {
            'n' { [void]$sb.Append([char]0x0A); $i++ }
            'r' { [void]$sb.Append([char]0x0D); $i++ }
            't' { [void]$sb.Append([char]0x09); $i++ }
            'v' { [void]$sb.Append([char]0x0B); $i++ }
            'b' { [void]$sb.Append([char]0x08); $i++ }
            'f' { [void]$sb.Append([char]0x0C); $i++ }
            'a' { [void]$sb.Append([char]0x07); $i++ }
            '"' { [void]$sb.Append('"');        $i++ }
            "'" { [void]$sb.Append("'");         $i++ }
            '\' { [void]$sb.Append('\');         $i++ }

            'x' {
                # \x followed by 1–4 hex digits
                $start = $i + 1; $len = 0
                while ($start + $len -lt $Value.Length -and $Value[$start + $len] -match '[0-9A-Fa-f]') {
                    $len++; if ($len -ge 4) { break }
                }
                if ($len -eq 0) { throw "Invalid \x escape at index $($i-1): missing hex digits." }
                $hex  = $Value.Substring($start, $len)
                $code = [Convert]::ToInt32($hex, 16)
                [void]$sb.Append([char]$code)
                $i += 1 + $len
            }

            { $_ -match '[0-7]' } {
                # Octal: up to 3 digits, first already in $esc
                $start = $i; $len = 1
                while ($len -lt 3 -and ($start + $len) -lt $Value.Length -and $Value[$start + $len] -match '^[0-7]$') {
                    $len++
                }
                $oct  = $Value.Substring($start, $len)
                $code = [Convert]::ToInt32($oct, 8)
                [void]$sb.Append([char]$code)
                $i += $len
            }

            default {
                # Unknown escape -> keep escaped char literally (drop the backslash)
                [void]$sb.Append($esc)
                $i++
            }
        }
    }
    $sb.ToString()
}


# ========================= Java escape / unescape =========================

function Escape-Java {
    param([string]$s)
    # Similar to C, but prefer \uXXXX for non-ASCII
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            "`t" { [void]$sb.Append('\t'); continue }
            "`n" { [void]$sb.Append('\n'); continue }
            "`r" { [void]$sb.Append('\r'); continue }
            "`b" { [void]$sb.Append('\b'); continue }
            "`f" { [void]$sb.Append('\f'); continue }
            '"'  { [void]$sb.Append('\"'); continue }
            "'"  { [void]$sb.Append("\'"); continue }
            '\'  { [void]$sb.Append("\\"); continue }
        }
        $code = [int]$ch
        if ($code -lt 0x20 -or $code -gt 0x7E) {
            [void]$sb.Append('\u' + $code.ToString('x4'))
        } else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}
function Unescape-Java {
    param([string]$s)
    $sb = New-Object System.Text.StringBuilder
    for ($i=0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($c -ne '\') { [void]$sb.Append($c); continue }
        if ($i + 1 -ge $s.Length) { [void]$sb.Append('\'); break }
        $i++
        switch ($s[$i]) {
            't' { [void]$sb.Append("`t") }
            'n' { [void]$sb.Append("`n") }
            'r' { [void]$sb.Append("`r") }
            'b' { [void]$sb.Append("`b") }
            'f' { [void]$sb.Append("`f") }
            '"' { [void]$sb.Append('"') }
            "'" { [void]$sb.Append("'") }
            '\' { [void]$sb.Append('\') }
            'u' {
                if ($i + 4 -ge $s.Length) { break }
                $hex = $s.Substring($i+1,4); $i += 4
                [void]$sb.Append([char]([Convert]::ToInt32($hex,16)))
            }
            default {
                # Java also accepts octal escapes \0..\377
                if ($s[$i] -match '[0-7]') {
                    $oct = $s[$i]
                    for ($k=0; $k -lt 2 -and ($i+1) -lt $s.Length -and $s[$i+1] -match '[0-7]'; $k++) {
                        $i++; $oct += $s[$i]
                    }
                    [void]$sb.Append([char]([Convert]::ToInt32($oct,8)))
                } else {
                    [void]$sb.Append($s[$i])
                }
            }
        }
    }
    return $sb.ToString()
}

function Filter-EscJava {
    <#
      .SYNOPSIS
        Escapes a string using Java-style sequences.

      .NOTES
        - Escapes: \\, \', \", \b, \t, \n, \f, \r
        - Control/non-ASCII -> \uXXXX
        - Supplementary code points -> two surrogate \uXXXX pairs (Java uses UTF-16)
    #>
    param([Parameter(Mandatory)][string]$Value)

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Value.Length) {
        $ch = $Value[$i]

        if ([char]::IsHighSurrogate($ch) -and $i + 1 -lt $Value.Length -and [char]::IsLowSurrogate($Value[$i+1])) {
            # Java expects surrogate pair as two \uXXXX
            $hi = [int][char]$ch
            $lo = [int][char]$Value[$i+1]
            [void]$sb.Append('\u')
            [void]$sb.Append(('{0:X4}' -f $hi))
            [void]$sb.Append('\u')
            [void]$sb.Append(('{0:X4}' -f $lo))
            $i += 2
            continue
        }

        $code = [int][char]$ch
        switch ($code) {
            92 { [void]$sb.Append('\'); [void]$sb.Append('\'); $i++; continue } # \
            34 { [void]$sb.Append('\'); [void]$sb.Append('"'); $i++; continue } # "
            39 { [void]$sb.Append('\'); [void]$sb.Append("'"); $i++; continue } # '

            8  { [void]$sb.Append('\'); [void]$sb.Append('b'); $i++; continue }
            9  { [void]$sb.Append('\'); [void]$sb.Append('t'); $i++; continue }
            10 { [void]$sb.Append('\'); [void]$sb.Append('n'); $i++; continue }
            12 { [void]$sb.Append('\'); [void]$sb.Append('f'); $i++; continue }
            13 { [void]$sb.Append('\'); [void]$sb.Append('r'); $i++; continue }
            0  { [void]$sb.Append('\'); [void]$sb.Append('0'); $i++; continue }
        }

        if ($code -lt 0x20 -or $code -gt 0x7E) {
            [void]$sb.Append('\u')
            [void]$sb.Append(('{0:X4}' -f $code))
            $i++
            continue
        }

        [void]$sb.Append($ch)
        $i++
    }
    $sb.ToString()
}


function Convert-CodePointToString {
    param([int]$cp)
    if ($cp -le 0xFFFF) { return [char]$cp }
    $cp -= 0x10000
    $hi = 0xD800 + ($cp -shr 10)
    $lo = 0xDC00 + ($cp -band 0x3FF)
    return ([char]$hi).ToString() + ([char]$lo)
}

# ========================= C# escape / unescape =========================

# Convert string to C#-style escape sequences:
function Escape-Cs {
    param([string]$s)
    $sb = New-Object System.Text.StringBuilder
    foreach ($ch in $s.ToCharArray()) {
        switch ($ch) {
            "`t" { [void]$sb.Append('\t'); continue }
            "`n" { [void]$sb.Append('\n'); continue }
            "`r" { [void]$sb.Append('\r'); continue }
            "`b" { [void]$sb.Append('\b'); continue }
            "`f" { [void]$sb.Append('\f'); continue }
            '"'  { [void]$sb.Append('\"'); continue }
            "'"  { [void]$sb.Append("\'"); continue }
            '\'  { [void]$sb.Append("\\"); continue }
        }
        $code = [int]$ch
        if ($code -lt 0x20 -or $code -gt 0x7E) {
            if ($code -le 0xFFFF) {
                [void]$sb.Append('\u' + $code.ToString('x4'))
            } else {
                [void]$sb.Append('\U' + $code.ToString('x8'))
            }
        } else {
            [void]$sb.Append($ch)
        }
    }
    return $sb.ToString()
}


# Convert string from C#-style escape sequences (old version, does not handle \x or octal):
function Unescape-Cs {
    param([string]$s)
    $sb = New-Object System.Text.StringBuilder
    for ($i=0; $i -lt $s.Length; $i++) {
        $c = $s[$i]
        if ($c -ne '\') { [void]$sb.Append($c); continue }
        if ($i + 1 -ge $s.Length) { [void]$sb.Append('\'); break }
        $i++
        switch ($s[$i]) {
            't' { [void]$sb.Append("`t") }
            'n' { [void]$sb.Append("`n") }
            'r' { [void]$sb.Append("`r") }
            'b' { [void]$sb.Append("`b") }
            'f' { [void]$sb.Append("`f") }
            '"' { [void]$sb.Append('"') }
            "'" { [void]$sb.Append("'") }
            '\' { [void]$sb.Append('\') }
            'u' {
                if ($i + 4 -ge $s.Length) { break }
                $hex = $s.Substring($i+1,4); $i += 4
                [void]$sb.Append([char]([Convert]::ToInt32($hex,16)))
            }
            'U' {
                if ($i + 8 -ge $s.Length) { break }
                $hex = $s.Substring($i+1,8); $i += 8
                $cp  = [Convert]::ToInt32($hex,16)
                [void]$sb.Append( (Convert-CodePointToString $cp) )
            }
            default { [void]$sb.Append($s[$i]) }
        }
    }
    return $sb.ToString()
}

# Convert string to C#-style escape sequences:
# Remove any previous definition to avoid mixing old logic
Remove-Item function:Filter-EscCs -ErrorAction SilentlyContinue

function Filter-EscCs {
    <#
      .SYNOPSIS
        Escapes a string using C#-style sequences (\", \', \\, \0, \a, \b, \f, \n, \r, \t, \v).
      .NOTES
        - Short escapes handled first; each branch appends once and `continue`s.
        - Other control chars (U+0000–001F, U+007F) -> \uXXXX
        - Supplementary code points (> U+FFFF) -> \UXXXXXXXX
    #>
    param([Parameter(Mandatory)][string]$Value)

    $sb = [System.Text.StringBuilder]::new()
    $i  = 0

    while ($i -lt $Value.Length) {
        $ch = $Value[$i]

        # 1) Supplementary code points as one \UXXXXXXXX token
        if ([char]::IsHighSurrogate($ch) -and $i + 1 -lt $Value.Length -and [char]::IsLowSurrogate($Value[$i + 1])) {
            $cp = [char]::ConvertToUtf32($ch, $Value[$i + 1])
            [void]$sb.Append('\U')
            [void]$sb.Append(('{0:X8}' -f $cp))
            $i += 2
            continue
        }

        $code = [int][char]$ch

        # 2) Short, explicit escapes — append and CONTINUE
        if     ($code -eq 92) { [void]$sb.Append('\\'); $i++; continue } # backslash \
        elseif ($code -eq 34) { [void]$sb.Append('\"'); $i++; continue } # double quote "
        elseif ($code -eq 39) { [void]$sb.Append("\'"); $i++; continue } # single quote '

        elseif ($code -eq 0 ) { [void]$sb.Append('\0'); $i++; continue }
        elseif ($code -eq 7 ) { [void]$sb.Append('\a'); $i++; continue }
        elseif ($code -eq 8 ) { [void]$sb.Append('\b'); $i++; continue }
        elseif ($code -eq 9 ) { [void]$sb.Append('\t'); $i++; continue }
        elseif ($code -eq 10) { [void]$sb.Append('\n'); $i++; continue }
        elseif ($code -eq 11) { [void]$sb.Append('\v'); $i++; continue }
        elseif ($code -eq 12) { [void]$sb.Append('\f'); $i++; continue }
        elseif ($code -eq 13) { [void]$sb.Append('\r'); $i++; continue }

        # 3) Other control chars (or DEL) -> \uXXXX (only if NOT matched above)
        elseif ($code -lt 0x20 -or $code -eq 0x7F) {
            [void]$sb.Append('\u')
            [void]$sb.Append(('{0:X4}' -f $code))
            $i++
            continue
        }

        # 4) Normal character
        [void]$sb.Append($ch)
        $i++
    }

    $sb.ToString()
}


# Convert string from C#-style escape sequences:
function Filter-FromEscCs {
    <#
      .SYNOPSIS
        Decodes C#-style escape sequences in a string.

      .NOTES
        Supported: \\, \', \", \a, \b, \f, \n, \r, \t, \v, \0,
                   \xH… (1–4 hex digits),
                   \uXXXX (exactly 4 hex digits),
                   \UXXXXXXXX (exactly 8 hex digits, full Unicode code point).
        C# does not define octal escapes; unknown escapes are treated as literal char (without the backslash).
    #>
    param([Parameter(Mandatory)][string]$Value)

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Value.Length) {
        $ch = $Value[$i]
        if ($ch -ne '\') {
            [void]$sb.Append($ch)
            $i++
            continue
        }

        $i++
        if ($i -ge $Value.Length) { [void]$sb.Append('\'); break }
        $esc = $Value[$i]

        switch -CaseSensitive ($esc) {
            'n' { [void]$sb.Append([char]0x0A); $i++ }
            'r' { [void]$sb.Append([char]0x0D); $i++ }
            't' { [void]$sb.Append([char]0x09); $i++ }
            'v' { [void]$sb.Append([char]0x0B); $i++ }
            'b' { [void]$sb.Append([char]0x08); $i++ }
            'f' { [void]$sb.Append([char]0x0C); $i++ }
            'a' { [void]$sb.Append([char]0x07); $i++ }
            '"' { [void]$sb.Append('"');        $i++ }
            "'" { [void]$sb.Append("'");         $i++ }
            '\' { [void]$sb.Append('\');         $i++ }

            'x' {
                # \x followed by 1–4 hex digits
                $start = $i + 1; $len = 0
                while ($start + $len -lt $Value.Length -and $Value[$start + $len] -match '[0-9A-Fa-f]') {
                    $len++; if ($len -ge 4) { break }
                }
                if ($len -eq 0) { throw "Invalid \x escape at index $($i-1): missing hex digits." }
                $hex  = $Value.Substring($start, $len)
                $code = [Convert]::ToInt32($hex, 16)
                [void]$sb.Append([char]$code)
                $i += 1 + $len
            }

            'u' {
                # \uXXXX (exactly 4 hex digits)
                if ($i + 4 -ge $Value.Length) { throw "Invalid \u escape at index $($i-1): requires 4 hex digits." }
                $hex = $Value.Substring($i + 1, 4)
                if ($hex -notmatch '^[0-9A-Fa-f]{4}$') { throw "Invalid \u escape at index $($i-1): '$hex'." }
                $code = [Convert]::ToInt32($hex, 16)
                [void]$sb.Append([char]$code)
                $i += 5
            }

            'U' {
                # \UXXXXXXXX (exactly 8 hex digits)
                if ($i + 8 -ge $Value.Length) { throw "Invalid \U escape at index $($i-1): requires 8 hex digits." }
                $hex = $Value.Substring($i + 1, 8)
                if ($hex -notmatch '^[0-9A-Fa-f]{8}$') { throw "Invalid \U escape at index $($i-1): '$hex'." }
                $cp = [Convert]::ToInt32($hex, 16)
                if ($cp -lt 0 -or $cp -gt 0x10FFFF) { throw "Invalid Unicode code point U+$hex at index $($i-1)." }
                if ($cp -le 0xFFFF) {
                    [void]$sb.Append([char]$cp)
                } else {
                    $v  = $cp - 0x10000
                    $hi = 0xD800 + ($v -shr 10)
                    $lo = 0xDC00 + ($v -band 0x3FF)
                    [void]$sb.Append([char]$hi)
                    [void]$sb.Append([char]$lo)
                }
                $i += 9
            }

            default {
                # Unknown escape -> keep escaped char literally (drop the backslash)
                [void]$sb.Append($esc)
                $i++
            }
        }
    }
    $sb.ToString()
}

# ---------------------------------------------------------------------------
# FILTERS: path manipulation filters
# Conversion to Windows or Linux paths, canonization w.r. the current OS.
# ---------------------------------------------------------------------------

# Changes path to absolute, normalizing it for Windows (backslashes, resolved 
# . and .., replacing duplicate backslashes).
function To-WindowsPathAbsolute($path) {
    # Resolve relative bits, normalize slashes
    $normalized = [System.IO.Path]::GetFullPath($path)

    # Ensure backslashes (in case input had forward slashes)
    return $normalized -replace '/', '\'
}

# Changes path to absolute, normalizing it for Linux (slashes, resolved 
# . and .., replacing duplicate slashes).
function To-LinuxPathAbsolute($path) {
    # Normalize using .NET first (removes ./, duplicate slashes, etc.)
    $normalized = [System.IO.Path]::GetFullPath($path)

    # Convert backslashes to forward slashes
    $normalized = $normalized -replace '\\', '/'

    # Replace drive letter (C:\ → /c/ style, like WSL/MinGW convention)
    if ($normalized -match '^([A-Za-z]):') {
        $drive = $matches[1].ToLower()
        $normalized = $normalized -replace '^.:', "/$drive"
    }

    return $normalized
}

# Converts path to absolute, normalized for the current OS.
function To-OSPathAbsolute($path) {
    if ($IsWindows) {
        return To-WindowsPathAbsolute $path
    } else {
        return To-LinuxPathAbsolute $path
    }
}

# Changes path to a canonical form for Windows, preserving relative paths.
function To-WindowsPathPreserveRelative($path) {
    # Convert all separators to backslash
    $p = $path -replace '/', '\'

    # Collapse duplicate backslashes (except for leading \\ in UNC paths)
    $p = $p -replace '(?<!^)(\\)\\+', '$1'

    # Remove "\.\" parts
    $p = $p -replace '\\\.(?=\\|$)', ''

    return $p
}

# Changes path to a canonical form for Linux, preserving relative paths.
function To-LinuxPathPreserveRelative($path) {
    # Convert all backslashes to forward slash
    $p = $path -replace '\\', '/'

    # Collapse duplicate slashes (but keep leading // for network paths if you want)
    $p = $p -replace '//+', '/'

    # Remove "/./" parts
    $p = $p -replace '/\.(?=/|$)', ''

    # Optional: map drive letters (C:\ → /c/) if path starts with them
    if ($p -match '^([A-Za-z]):') {
        $drive = $matches[1].ToLower()
        $p = $p -replace '^.:', "/$drive"
    }

    return $p
}

# Changes path to a canonical form for the current OS, preserving relative paths.
function To-OSPathPreserveRelative($path) {
    if ($IsWindows) {
        return To-WindowsPathPreserveRelative $path
    } else {
        return To-LinuxPathPreserveRelative $path
    }
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
        [object]   $Value,     # can be string or [byte[]] between filters
        [object[]] $Pipeline
    )

    foreach ($f in $Pipeline) {

        # ---- Normalize access for hashtable or PSCustomObject ----
        $isHash = ($f -is [hashtable])

        $name = if ($isHash) { [string]$f['name'] } else { [string]$f.name }
        $arg  = if ($isHash) { $f['arg'] }         else { $f.arg }

        # multi-arg support (e.g., replace:"old":"new")
        $args = @()
        if ($isHash) {
            if ($f.ContainsKey('args') -and $f['args']) { $args = @($f['args']) }
            elseif ($null -ne $arg) { $args = @($arg) }
        } else {
            if ($f.PSObject.Properties['args'] -and $f.args) { $args = $f.args }
            elseif ($null -ne $arg) { $args = @($arg) }
        }

        switch ($name.ToLowerInvariant()) {

            # -------------------- Basic string transforms --------------------
            'trim'   { $Value = (As-String $Value).Trim() }
            'upper'  { $Value = (As-String $Value).ToUpper() }
            'lower'  { $Value = (As-String $Value).ToLower() }

            # -------------------- Quoting / escaping (text) ------------------
            'quote'      { $Value = '"' + (As-String $Value) + '"' }
            'pathquote'  {
                $s = As-String $Value
                if ($s -notmatch '^\s*".*"\s*$') { $s = '"' + $s + '"' }
                $Value = $s
            }
            'regq'    { $Value = (As-String $Value) -replace '"','\"' }
            'regesc'  { $Value = ((As-String $Value) -replace '\\','\\') -replace '"','\"' }

            # -------------------- Path normalization (your helpers) ----------
            'pathwin'     { $Value = To-WindowsPathPreserveRelative (As-String $Value) }
            'pathlinux'   { $Value = To-LinuxPathPreserveRelative   (As-String $Value) }
            'pathos'      { $Value = To-OSPathPreserveRelative      (As-String $Value) }
            'pathwinabs'  { $Value = To-WindowsPathAbsolute         (As-String $Value) }
            'pathlinuxabs'{ $Value = To-LinuxPathAbsolute           (As-String $Value) }
            'pathosabs'   { $Value = To-OSPathAbsolute              (As-String $Value) }

            # -------------------- String composition -------------------------
            'prepend'     { $Value = ($(if ($null -ne $arg) { $arg } else { '' })) + (As-String $Value) }
            'append'      { $Value = (As-String $Value) + ($(if ($null -ne $arg) { $arg } else { '' })) }
            'default'     {
                $s = As-String $Value
                if ([string]::IsNullOrWhiteSpace($s)) {
                    $Value = ($(if ($null -ne $arg) { $arg } else { '' }))
                } else {
                    $Value = $s
                }
            }
            'replace'     {
                if ($args.Count -lt 2) { throw 'replace filter requires two arguments: replace:"old":"new"' }
                $old = $args[0]; $new = $args[1]
                $Value = (As-String $Value).Replace($old, $new)   # literal, not regex
            }
            'pathappend'  { $Value = (As-String $Value) + ($(if ($null -ne $arg) { $arg } else { '' })) }
            'addarg'      { $Value = (As-String $Value) + ' "' + ($(if ($null -ne $arg) { $arg } else { '' })) + '"' }

            # ----------------- Bytes-to-text and vice versa -------------------
            # Decode byte[] -> string using UTF-16LE (.NET "Unicode" string)
            'utf16' { 
                # expects byte[]
                $Value = [System.Text.Encoding]::Unicode.GetString($value)
            }
            # Decode byte[] -> string using UTF-8
            'utf8' {
                $bytes = As-Bytes $Value
                $Value = [System.Text.Encoding]::UTF8.GetString($bytes)
            }
            # Force string -> byte[] using UTF-16LE (symmetry helper):
            'bytes' {
                $Value = As-Bytes $Value   # already returns Unicode bytes
            }
            # Returns type of the value (for debugging purposes)
            'type' {
              $Value = ($Value).GetType().FullName
            }
            
            # -------------------- Text encodings ------------------------------
            'urlencode'   { $Value = Filter-UrlEncode (As-String $Value) }
            'urldecode'   { $Value = Filter-UrlDecode (As-String $Value) }

            'xmlencode'   { $Value = Filter-XmlEncode (As-String $Value) }
            'xmldecode'   { $Value = Filter-XmlDecode (As-String $Value) }

            # -------------------- Binary/text codecs -------------------------
            
            # Compress string or byte[] → byte[] with gzip
            'gzip'        { $Value = Filter-Gzip      $Value }  # -> byte[]
            # Unzip byte[] → string (UTF-16LE, .NET "Unicode" string):
            'strgunzip'   { $Value = [Text.Encoding]::Unicode.GetString( (Filter-Gunzip $Value) ) }  # byte[] -> byte[] -> string
            # Uncompress byte[] → byte[] with gzip (needs additional utf16 filter to get string):
            'gunzip' { 
              $bytes = Filter-Gunzip    $Value 
                if ($args.Count -gt 0) {
                    switch ($args[0].ToLower()) {
                        'utf16'  { $Value = [Text.Encoding]::Unicode.GetString($bytes) }
                        default  { throw "gunzip: unknown decode '$($args[0])' (use utf16)" }
                    }
                } else {
                    $Value = $bytes  # binary mode (for chaining into utf16, base64, etc.)
                }
            }

            # Encode string or byte[] → base64 string
            'base64'      { $Value = Filter-Base64    $Value }  # bytes or string -> base64 string
            # Decode base64 → string (UTF-16LE, .NET "Unicode" string)
            'strfrombase64' { $Value = [Text.Encoding]::Unicode.GetString( (Filter-FromBase64 $Value) ) }
            # Decode base64 → Byte[], with optional filters for final conversion to
            # encoded string:
            'frombase64' {
                $bytes = Filter-FromBase64 $Value
                if ($args.Count -gt 0) {
                    switch ($args[0].ToLower()) {
                        'utf16'  { $Value = [Text.Encoding]::Unicode.GetString($bytes) }
                        'utf8'   { $Value = [Text.Encoding]::UTF8.GetString($bytes) }
                        'ascii'  { $Value = [Text.Encoding]::ASCII.GetString($bytes) }
                        'latin1' { $Value = [Text.Encoding]::GetEncoding(28591).GetString($bytes) }
                        default  { throw "frombase64: unknown decode '$($args[0])' (use utf16|utf8|ascii|latin1)" }
                    }
                } else {
                    $Value = $bytes  # binary mode (for chaining into gzip, etc.)
                }
            }

            # Encode string or byte[] → hex lowercase string
            'hex'         { $Value = Filter-Hex       $Value }  # bytes or string -> hex string
            # Decode hex → string (UTF-16LE, .NET "Unicode" string)
            'strfromhex'    { $Value = [Text.Encoding]::Unicode.GetString( (Filter-FromHex     $Value) ) }            
            # Decode hex → Byte[], with optional filters for final conversion to
            # encoded string:
            'fromhex' {
                $bytes = Filter-FromHex $Value
                if ($args.Count -gt 0) {
                    switch ($args[0].ToLower()) {
                        'utf16'  { $Value = [Text.Encoding]::Unicode.GetString($bytes) }
                        'utf8'   { $Value = [Text.Encoding]::UTF8.GetString($bytes) }
                        'ascii'  { $Value = [Text.Encoding]::ASCII.GetString($bytes) }
                        'latin1' { $Value = [Text.Encoding]::GetEncoding(28591).GetString($bytes) }
                        default  { throw "fromhex: unknown decode '$($args[0])' (use utf16|utf8|ascii|latin1)" }
                    }
                } else {
                    $Value = $bytes
                }
            }

            # -------------------- Programming-language escapes ---------------
            'escc' { 
              # $Value = Escape-C         (As-String $Value) 
              $Value = Filter-EscC (As-String $Value)
            }
            'fromescc' { 
                # $Value = Unescape-C       (As-String $Value) 
                $Value = Filter-FromEscC (As-String $Value)
            }

            'escjava'     { 
                # $Value = Escape-Java      (As-String $Value)
                $Value = Filter-EscJava      (As-String $Value)
            }
            'fromescjava' { 
                $Value = Unescape-Java    (As-String $Value) 
                # $Value = Filter-FromEscJava    (As-String $Value) 
           }

            'esccs' { 
                # $Value = Escape-Cs (As-String $Value) 
                $Value = Filter-EscCs (As-String $Value) 
            }
            'fromesccs'  { 
                $Value = Filter-FromEscCs (As-String $Value) 
            }

            # -------------------- .reg specific ------------------------------
            'expandsz' {
                $s     = As-String $Value
                $bytes = [System.Text.Encoding]::Unicode.GetBytes($s + [char]0)
                $hex   = ($bytes | ForEach-Object { $_.ToString('x2') }) -join ','
                $Value = 'hex(2):' + $hex
            }

            default {
                throw "Unknown filter '${name}'."
            }
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

# Temporarily transform double curly brackets escaping:
$tplText = $tplText -replace "\\{{", "\{\{"
$tplText = $tplText -replace "\\}}", "\}\}"

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
            if (-not $out -is [string]) {
                Write-Warning "  Final value is not a string:"
                Write-Host "  ${out}"
                Write-Host "  Type: $($out.GetType().FullName))"
            }
            # If a pipeline ends as byte[], force the template author to finish with base64/hex/gunzip/etc.
            if (Is-ByteVector $out) {
                throw "Placeholder resulted in binary data. Add a final text-producing filter (e.g., base64, hex, gunzip, utf16)."
            }            
            return $out
        } catch {
            $errors.Add("Error in placeholder '{{ ${expr} }}': $($_.Exception.Message)")
            return "<ERROR:$expr>"
        }
    }
)

# Backward transform double curly brackets escaping:
$expanded = $expanded -replace "\\{\\{", "{{"
$expanded = $expanded -replace "\\}\\}", "}}"

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