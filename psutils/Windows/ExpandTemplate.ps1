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

$Debug = $true  # Enable debug messages for development

# Debug/Verbose mode flags:
$script:VerboseMode = $true  # Set to $true to enable debug messages
$script:DebugMode = $true    # Set to $true to enable debug messages

# Console colors:
# Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, 
# DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White
# Console colors for messages:
$script:FgVerbose = "Gray"    # Verbose messages color
$script:FgDebug = "DarkGray"  # Debug messages color

function Write-Verbose {
  param([string]$Msg)
  if ($null -eq $script:FgVerbose) { $script:FgVerbose = "Gray" }
  if ($script:VerboseMode) { Write-Host "$Msg" -ForegroundColor $script:FgVerbose }
}

function Write-Debug {
  param([string]$Msg)
  if ($null -eq $script:FgDebug) { $script:FgDebug = "DarkGray" }
  if ($script:DebugMode) { Write-Host "$Msg" -ForegroundColor $script:FgDebug }
}

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

# Convert a literal string to a C/C++-style escaped string.
# Rules:
#   - Standard short escapes: \0 \a \b \t \n \v \f \r \" \' \? \\
#   - Other control chars (and DEL 0x7F): \u00HH (fixed-length, unambiguous)
#   - Printable ASCII (0x20..0x7E except the ones above): literal
#   - Non-ASCII BMP (<= 0xFFFF): \uXXXX
#   - Non-BMP (> 0xFFFF): \UXXXXXXXX (surrogate pair form)
function Filter-EscC {
    param([Parameter(Mandatory)][string]$Text)

    $sb = [System.Text.StringBuilder]::new()

    function Append-UnicodeEscape([System.Text.StringBuilder]$B, [int]$cp) {
        if ($cp -le 0xFFFF) {
            [void]$B.Append('\u')
            [void]$B.Append($cp.ToString('X4'))
        } else {
            [void]$B.Append('\U')
            [void]$B.Append($cp.ToString('X8'))
        }
    }

    $i   = 0
    $len = $Text.Length
    while ($i -lt $len) {
        $c = [int][char]$Text[$i]

        # Detect surrogate pair (no System.Text.Rune dependency)
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and ($i + 1) -lt $len) {
            $c2 = [int][char]$Text[$i+1]
            if ($c2 -ge 0xDC00 -and $c2 -le 0xDFFF) {
                $cp = (($c - 0xD800) -shl 10) + ($c2 - 0xDC00) + 0x10000
                Append-UnicodeEscape $sb $cp
                $i += 2
                continue
            }
        }

        switch ($c) {
            0x00 { [void]$sb.Append('\0');  $i++; continue }
            0x07 { [void]$sb.Append('\a');  $i++; continue }
            0x08 { [void]$sb.Append('\b');  $i++; continue }
            0x09 { [void]$sb.Append('\t');  $i++; continue }
            0x0A { [void]$sb.Append('\n');  $i++; continue }
            0x0B { [void]$sb.Append('\v');  $i++; continue }
            0x0C { [void]$sb.Append('\f');  $i++; continue }
            0x0D { [void]$sb.Append('\r');  $i++; continue }
            0x22 { [void]$sb.Append('\"');  $i++; continue } # "
            0x27 { [void]$sb.Append("\'");  $i++; continue } # '
            0x3F { [void]$sb.Append('\?');  $i++; continue } # ?
            0x5C { [void]$sb.Append('\\');  $i++; continue } # backslash

            default {
                if ($c -lt 0x20 -or $c -eq 0x7F) {
                    # Other control chars → canonical, fixed-length \u00HH
                    [void]$sb.Append('\u')
                    # build 4 hex digits with leading zeros for the low byte
                    [void]$sb.Append(('00' + $c.ToString('X2'))[-4..-1] -join '')
                    $i++
                }
                elseif ($c -le 0x7E) {
                    # Printable ASCII
                    [void]$sb.Append([char]$c)
                    $i++
                }
                else {
                    # Non-ASCII → \uXXXX or \UXXXXXXXX
                    Append-UnicodeEscape $sb $c
                    $i++
                }
            }
        }
    }

    $sb.ToString()
}

# Convert string including C/C++-style escape sequences to literal string:
function Filter-FromEscC {
    param([Parameter(Mandatory)][string]$Text)

    # --- PRE-PASS: normalize \UXXXXXXXX to real Unicode (surrogate pairs as needed) ---
    $Text = [System.Text.RegularExpressions.Regex]::Replace(
        $Text,
        '\\U([0-9A-Fa-f]{8})',
        { param($m)
            $hex = $m.Groups[1].Value
            $cp  = [Convert]::ToInt32($hex, 16)
            if ($cp -gt 0x10FFFF -or ($cp -ge 0xD800 -and $cp -le 0xDFFF)) {
                throw "Invalid Unicode code point U+$($hex.ToUpper())."
            }
            [System.Char]::ConvertFromUtf32($cp)
        }
    )

    $sb  = [System.Text.StringBuilder]::new()
    $i   = 0
    $len = $Text.Length

    function Parse-Hex([string]$s) {
        $v = 0
        if (-not [int]::TryParse($s,
            [System.Globalization.NumberStyles]::AllowHexSpecifier,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$v)) {
            throw "Invalid hex digits '$s'."
        }
        $v
    }

    function Append-CodePoint([System.Text.StringBuilder]$B, [int]$cp) {
        if ($cp -le 0xFFFF) {
            [void]$B.Append([char]$cp)
        } else {
            $pair = [System.Char]::ConvertFromUtf32($cp)
            [void]$B.Append($pair)
        }
    }

    while ($i -lt $len) {
        $ch = $Text[$i]
        if ($ch -ne '\') { [void]$sb.Append($ch); $i++; continue }

        if ($i + 1 -ge $len) { [void]$sb.Append('\'); break }
        $i++
        $esc = $Text[$i]

        switch ($esc) {
            'a' { [void]$sb.Append([char]0x07); $i++; continue }
            'b' { [void]$sb.Append([char]0x08); $i++; continue }
            't' { [void]$sb.Append([char]0x09); $i++; continue }
            'n' { [void]$sb.Append([char]0x0A); $i++; continue }
            'v' { [void]$sb.Append([char]0x0B); $i++; continue }
            'f' { [void]$sb.Append([char]0x0C); $i++; continue }
            'r' { [void]$sb.Append([char]0x0D); $i++; continue }
            '"' { [void]$sb.Append('"');       $i++; continue }
            "'" { [void]$sb.Append("'");       $i++; continue }
            '?' { [void]$sb.Append('?');       $i++; continue }
            '\' { [void]$sb.Append('\');       $i++; continue }

            'x' {
                # \xHH... : 1–8 hex digits (greedy)
                $start = $i + 1
                $j = $start
                while ($j -lt $len -and (
                        ($Text[$j] -ge '0' -and $Text[$j] -le '9') -or
                        ($Text[$j] -ge 'a' -and $Text[$j] -le 'f') -or
                        ($Text[$j] -ge 'A' -and $Text[$j] -le 'F'))) {
                    if (($j - $start) -ge 8) { break }
                    $j++
                }
                if ($j -eq $start) { throw "Invalid \x escape at index ${i}: expected 1+ hex digits." }
                $hex = $Text.Substring($start, $j - $start)
                $val = Parse-Hex $hex
                Append-CodePoint $sb $val
                $i = $j
                continue
            }

            'u' {
                # \uXXXX (exactly 4 hex)
                if (($i + 4) -ge $len) { throw "Invalid \u escape at index ${i}: expected 4 hex digits." }
                $hex = $Text.Substring($i + 1, 4)
                if ($hex -notmatch '^[0-9A-Fa-f]{4}$') { throw "Invalid \u escape digits '$hex' at index $i." }
                $val = Parse-Hex $hex
                Append-CodePoint $sb $val
                $i += 5
                continue
            }

            'U' {
                # \UXXXXXXXX already normalized by pre-pass; keep as literal in case one slipped through
                [void]$sb.Append('U')
                $i++
                continue
            }

            default {
                # Octal: \[0-7]{1,3}
                if ($esc -ge '0' -and $esc -le '7') {
                    $start  = $i
                    $digits = 1
                    while ($digits -lt 3 -and $i + 1 -lt $len -and $Text[$i+1] -ge '0' -and $Text[$i+1] -le '7') {
                        $i++; $digits++
                    }
                    $oct = $Text.Substring($start, $digits)
                    $val = [Convert]::ToInt32($oct, 8)
                    Append-CodePoint $sb $val
                    $i = $start + $digits
                    continue
                }

                # Unknown escape => take next char literally
                [void]$sb.Append($esc)
                $i++
                continue
            }
        }
    }

    $sb.ToString()
}



# ========================= Java escape / unescape =========================

# Convert string to include Java-style escape sequences:
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

# Convert string from including Java-style escape sequences to literal (old version):
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

# Convert literal strings to include Java-style escape sequences:
function Filter-EscJava {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $sb = New-Object System.Text.StringBuilder

    # Emit one UTF-16 code unit as Java \uXXXX
    function _Emit-U { param([int]$unit) [void]$sb.Append(('\u{0:X4}' -f $unit)) }

    $enum = [System.Globalization.StringInfo]::GetTextElementEnumerator($Text)
    while ($enum.MoveNext()) {
        $te = $enum.GetTextElement()

        # Scalar codepoint of this text element (handles BMP and surrogate pairs)
        $cp = [char]::ConvertToUtf32($te, 0)

        if ($cp -le 0xFFFF) {
            # Single UTF-16 unit (BMP)
            $ch = [char]$cp
            switch ($ch) {
                '"'  { [void]$sb.Append('\"'); continue }
                "'"  { [void]$sb.Append("\'"); continue }
                '\'  { [void]$sb.Append('\\'); continue }
                "`b" { [void]$sb.Append('\b'); continue }
                "`t" { [void]$sb.Append('\t'); continue }
                "`n" { [void]$sb.Append('\n'); continue }
                "`f" { [void]$sb.Append('\f'); continue }
                "`r" { [void]$sb.Append('\r'); continue }
                default {
                    # Keep printable ASCII literal; escape control/non-ASCII as \uXXXX
                    $code = [int]$ch
                    if ([char]::IsControl($ch) -or $code -lt 0x20 -or $code -gt 0x7E) {
                        _Emit-U $code
                    } else {
                        [void]$sb.Append($ch)
                    }
                }
            }
        } else {
            # Supplementary plane: emit surrogate pair as two \uXXXX (Java canonical form)
            $tmp  = $cp - 0x10000
            $high = 0xD800 + ($tmp -shr 10)
            $low  = 0xDC00 + ($tmp -band 0x3FF)
            _Emit-U $high
            _Emit-U $low
        }
    }

    $sb.ToString()
}

# Convert strings including Java-style escape sequences to literal form:
function Filter-FromEscJava {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $sb  = New-Object System.Text.StringBuilder
    $len = $Text.Length
    $i   = 0

    :outer while ($i -lt $len) {
        $ch = $Text[$i]
        if ($ch -ne '\') { [void]$sb.Append($ch); $i++; continue outer }

        if ($i + 1 -ge $len) { [void]$sb.Append('\'); break }
        $i++
        $esc = $Text[$i]

        switch -CaseSensitive ($esc) {
            'b' { [void]$sb.Append([char]8)  ; $i++; continue outer }
            't' { [void]$sb.Append([char]9)  ; $i++; continue outer }
            'n' { [void]$sb.Append([char]10) ; $i++; continue outer }
            'f' { [void]$sb.Append([char]12) ; $i++; continue outer }
            'r' { [void]$sb.Append([char]13) ; $i++; continue outer }
            '"' { [void]$sb.Append('"')      ; $i++; continue outer }
            "'" { [void]$sb.Append("'")      ; $i++; continue outer }
            '\' { [void]$sb.Append('\')      ; $i++; continue outer }

            # \uXXXX — exactly 4 hex digits per Java spec
            'u' {
                if ($i + 4 -ge $len) { [void]$sb.Append('\'); [void]$sb.Append('u'); $i++; continue outer }
                $hex = $Text.Substring($i+1,4)
                if ($hex -notmatch '^[0-9A-Fa-f]{4}$') {
                    [void]$sb.Append('\'); [void]$sb.Append("u$hex"); $i += 5; continue outer
                }
                $unit = [Convert]::ToInt32($hex,16)
                [void]$sb.Append([char]$unit)
                $i += 5

                # If we appended a high surrogate and the next thing is \uDCxx, append it (pair)
                if ($unit -ge 0xD800 -and $unit -le 0xDBFF) {
                    if ($i + 5 -le $len -and $Text[$i] -eq '\' -and $Text[$i+1] -eq 'u') {
                        $hex2 = $Text.Substring($i+2,4)
                        if ($hex2 -match '^[0-9A-Fa-f]{4}$') {
                            $unit2 = [Convert]::ToInt32($hex2,16)
                            if ($unit2 -ge 0xDC00 -and $unit2 -le 0xDFFF) {
                                [void]$sb.Append([char]$unit2)
                                $i += 6
                            }
                        }
                    }
                }
                continue outer
            }

            # Legacy Java octal escapes: \0 .. \377 (up to 3 octal digits)
            { $_ -ge '0' -and $_ -le '7' } {
                $start  = $i
                $digits = 1
                while ($digits -lt 3 -and $i + 1 -lt $len -and $Text[$i+1] -ge '0' -and $Text[$i+1] -le '7') {
                    $i++; $digits++
                }
                $oct = $Text.Substring($start, $digits)
                $val = [Convert]::ToInt32($oct, 8)
                [void]$sb.Append([char]$val)
                $i++
                continue outer
            }

            default {
                # Not a recognized Java escape — keep literally
                [void]$sb.Append('\'); [void]$sb.Append($esc); $i++; continue outer
            }
        }
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

# Convert literal string to include C#-style escape sequences:
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


# Convert string from including C#-style escape sequences to literal form (old version):
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

# Convert literal string to include C#-style escape sequences:

function Filter-EscCs {
    <#
      C#-style escape:
        - Short escapes for \n \r \t \v \b \f \0 \\ \" \'
        - Printable ASCII → literal
        - Other BMP → \uXXXX
        - Supplementary → \UXXXXXXXX
      Uses labeled loop so each char is emitted exactly once.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $sb  = New-Object System.Text.StringBuilder
    $len = $Text.Length
    $i   = 0

    :outer while ($i -lt $len) {
        $ch = $Text[$i]

        # Surrogate pair → \UXXXXXXXX
        if ([char]::IsHighSurrogate($ch) -and $i + 1 -lt $len -and [char]::IsLowSurrogate($Text[$i+1])) {
            $high   = [uint32][char]$ch
            $low    = [uint32][char]$Text[$i+1]
            $scalar = 0x10000 + (($high - 0xD800) -shl 10) + ($low - 0xDC00)
            [void]$sb.Append(('\U{0}' -f $scalar.ToString('X8')))
            $i += 2
            continue outer
        }

        $code = [int][char]$ch
        switch ($code) {
            10 { [void]$sb.Append('\n');  $i++; continue outer }  # LF
            13 { [void]$sb.Append('\r');  $i++; continue outer }  # CR
            9  { [void]$sb.Append('\t');  $i++; continue outer }  # HT
            11 { [void]$sb.Append('\v');  $i++; continue outer }  # VT
            8  { [void]$sb.Append('\b');  $i++; continue outer }  # BS
            12 { [void]$sb.Append('\f');  $i++; continue outer }  # FF
            0  { [void]$sb.Append('\0');  $i++; continue outer }  # NUL
            34 { [void]$sb.Append('\"');  $i++; continue outer }  # "
            39 { [void]$sb.Append("\'");  $i++; continue outer }  # '
            92 { [void]$sb.Append('\\');  $i++; continue outer }  # \
        }

        if ($code -lt 0x20 -or $code -eq 0x7F) {
            [void]$sb.Append(('\u{0}' -f $code.ToString('X4')))
            $i++; continue outer
        }

        if ($code -lt 0x80) {
            [void]$sb.Append([char]$code)
            $i++; continue outer
        }

        [void]$sb.Append(('\u{0}' -f $code.ToString('X4')))
        $i++; continue outer
    }

    $sb.ToString()
}

# Convert string including C#-style escape sequences to literal form:
function Filter-FromEscCs {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Text)

    $sb  = New-Object System.Text.StringBuilder
    $len = $Text.Length
    $i   = 0

    :outer while ($i -lt $len) {
        $ch = $Text[$i]
        if ($ch -ne '\') { [void]$sb.Append($ch); $i++; continue outer }

        if ($i + 1 -ge $len) { [void]$sb.Append('\'); break }
        $i++
        $esc = $Text[$i]

        switch -CaseSensitive ($esc) {
            'a' { [void]$sb.Append([char]7)  ; $i++; continue outer }
            'b' { [void]$sb.Append([char]8)  ; $i++; continue outer }
            'f' { [void]$sb.Append([char]12) ; $i++; continue outer }
            'n' { [void]$sb.Append([char]10) ; $i++; continue outer }
            'r' { [void]$sb.Append([char]13) ; $i++; continue outer }
            't' { [void]$sb.Append([char]9)  ; $i++; continue outer }
            'v' { [void]$sb.Append([char]11) ; $i++; continue outer }
            '0' { [void]$sb.Append([char]0)  ; $i++; continue outer }
            '"' { [void]$sb.Append('"')      ; $i++; continue outer }
            "'" { [void]$sb.Append("'")      ; $i++; continue outer }
            '\' { [void]$sb.Append('\')      ; $i++; continue outer }

            'x' {
                $i++
                $start  = $i
                $digits = 0
                while ($i -lt $len -and $digits -lt 4 -and [System.Uri]::IsHexDigit($Text[$i])) { $digits++; $i++ }
                if ($digits -eq 0) {
                    [void]$sb.Append('\'); [void]$sb.Append('x')
                } else {
                    $unit = [Convert]::ToInt32($Text.Substring($start,$digits),16)
                    [void]$sb.Append([char]$unit)
                }
                continue outer
            }

            'u' {
                if ($i + 4 -ge $len) { [void]$sb.Append('\'); [void]$sb.Append('u'); $i++; continue outer }
                $hex = $Text.Substring($i+1,4)
                if ($hex -notmatch '^[0-9A-Fa-f]{4}$') { [void]$sb.Append('\'); [void]$sb.Append("u$hex"); $i+=5; continue outer }
                $unit = [Convert]::ToInt32($hex,16)
                [void]$sb.Append([char]$unit)
                $i += 5
                continue outer
            }

            'U' {
                if ($i + 8 -ge $len) { [void]$sb.Append('\'); [void]$sb.Append('U'); $i++; continue outer }
                $hex = $Text.Substring($i+1,8)
                if ($hex -notmatch '^[0-9A-Fa-f]{8}$') { [void]$sb.Append('\'); [void]$sb.Append("U$hex"); $i+=9; continue outer }
                [uint32]$scalar = [Convert]::ToUInt32($hex,16)
                if ($scalar -le 0xFFFF) {
                    [void]$sb.Append([char]$scalar)
                } else {
                    $tmp  = $scalar - 0x10000
                    $high = 0xD800 + ($tmp -shr 10)
                    $low  = 0xDC00 + ($tmp -band 0x3FF)
                    [void]$sb.Append([char]$high)
                    [void]$sb.Append([char]$low)
                }
                $i += 9
                continue outer
            }

            default {
                # Not a recognized C# escape (e.g., \012): keep literally
                [void]$sb.Append('\'); [void]$sb.Append($esc); $i++; continue outer
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


    # --- SAFE debug/trace preamble (does not call methods on $null) ---

    # Normalize $Pipeline to an empty array if it's $null, so enumerations are safe.
    if ($null -eq $Pipeline) { $Pipeline = @() }

    # Build a readable preview of the incoming value without calling methods on $null
    $__valPreview = if ($null -eq $Value) { '<null>' } else { "'$Value'" }

    # Build a readable preview of the pipeline; safe even if empty
    $__pipePreview = if ($Pipeline.Count) {
        ($Pipeline | ForEach-Object {
            $n = $_.Name
            $a = if ($_.Args -and $_.Args.Count) {
                ($_.Args | ForEach-Object { '"{0}"' -f $_ }) -join ':'
            } else { '' }
            if ($a) { ('{0}:{1}' -f $n, $a) } else { $n }
        }) -join ' | '
    } else {
        '<none>'
    }

    Write-Debug ("Apply-Filters: in={0} | {1}" -f $__valPreview, $__pipePreview)

    # (Optional) per-filter trace—also null-safe:
    foreach ($__f in $Pipeline) {
        $n = $__f.Name
        $a = if ($__f.Args -and $__f.Args.Count) {
            ($__f.Args | ForEach-Object { '"{0}"' -f $_ }) -join ', '
        } else { '' }
        Write-Debug ('  -> {0}({1})' -f $n, $a)
    }
    # --- end SAFE preamble ---


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

        # --- diagnostic: show each filter before applying ---
        # if ($Debug) {
        #     $argList = if ($args) { ($args -join '", "') } else { '' }
        #     Write-Host ("[Apply-Filters] filter={0} args=[{1}] type(Value)={2}" -f `
        #         $name, $argList, ($Value?.GetType().FullName)) -ForegroundColor Yellow
        # }


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
                # $Value = Unescape-Java    (As-String $Value) 
                $Value = Filter-FromEscJava  (As-String $Value) 
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

        if ($Debug) {
            Write-Host ("[Apply-Filters] after {0} -> '{1}'" -f $name, ($Value -as [string])) `
                -ForegroundColor DarkYellow
        }

    }

    return $Value
}

function Normalize-Whitespace {
  param([string]$Text)
  if ($null -eq $Text) { return '' }
  # Collapse any CRLF/CR/LF and runs of whitespace to single spaces
  ($Text -replace '[\r\n]+',' ') -replace '\s+',' '
}

function Read-NextArg {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][ref]$Index
  )
  # Skips whitespace, then returns an argument string.
  # Supports quoted args: "like this", with \" \\ escapes.
  # Supports unquoted args until one of: space, tab, newline, ':', '|', '}'
  $i = $Index.Value
  $len = $Text.Length

  # skip spaces
  while ($i -lt $len -and ($Text[$i] -match '[ \t\r\n]')) { $i++ }
  if ($i -ge $len) { $Index.Value = $i; return "" }

  if ($Text[$i] -eq '"') {
    # quoted
    $i++  # consume opening "
    $sb = [System.Text.StringBuilder]::new()
    while ($i -lt $len) {
      $ch = $Text[$i]
      if ($ch -eq '"') { $i++; break }
      
      # Quoted-argument branch (handle escape sequences)
      if ($ch -eq '\') {
        if ($i + 1 -lt $len) {
          $n = $Text[$i + 1]
          if ($n -eq '"') {
            [void]$sb.Append('"');  $i += 2; continue
          } elseif ($n -eq '\') {
            [void]$sb.Append('\');  $i += 2; continue
          } else {
            # Preserve unknown escapes literally: append "\" and the next char.
            [void]$sb.Append('\')
            [void]$sb.Append($n)
            $i += 2
            continue
          }
        } else {
          # Trailing backslash before closing quote -> keep it
          [void]$sb.Append('\')
          $i += 1
          continue
        }
      }

      [void]$sb.Append($ch); $i++
    }
    $Index.Value = $i
    return $sb.ToString()
  }

  # unquoted
  $start = $i
  while ($i -lt $len) {
    $ch = $Text[$i]
    if ($ch -match '[ \t\r\n]') { break }
    if ($ch -in @(':','|','}')) { break }
    $i++
  }
  $Index.Value = $i
  return $Text.Substring($start, $i - $start)
}

function Tokenize-Pipeline {
  param(
    [Parameter(Mandatory)][string]$Inner  # text between {{ and }}
  )
  # Returns a PSCustomObject:
  #   Head     = 'var.Name' or 'env.NAME'
  #   Pipeline = @(@{Name='trim'; Args=@()}, @{Name='replace'; Args=@('a','b')}, ...)
  #
  # It respects quotes and allows unquoted filter args (no spaces/:/|/}).
  $i = 0
  $len = $Inner.Length

  # skip leading whitespace
  while ($i -lt $len -and ($Inner[$i] -match '[ \t\r\n]')) { $i++ }
  if ($i -ge $len) { throw "Empty placeholder." }

  # read head token up to whitespace or '|'
  $headStart = $i
  while ($i -lt $len) {
    $ch = $Inner[$i]
    if ($ch -eq '|') { break }
    if ($ch -match '[ \t\r\n]') { break }
    $i++
  }
  $head = $Inner.Substring($headStart, $i - $headStart).Trim()
  if (-not $head) { throw "Invalid placeholder head (empty)." }

  # skip spaces
  while ($i -lt $len -and ($Inner[$i] -match '[ \t\r\n]')) { $i++ }

  $pipeline = @()

  while ($i -lt $len) {
    if ($Inner[$i] -eq '|') {
      $i++  # consume pipe
      while ($i -lt $len -and ($Inner[$i] -match '[ \t\r\n]')) { $i++ }
      if ($i -ge $len) { break }

      # read filter name
      $nameStart = $i
      while ($i -lt $len) {
        $ch = $Inner[$i]
        if ($ch -match '[ \t\r\n:]') { break }
        if ($ch -eq '|') { break }
        $i++
      }
      $fname = $Inner.Substring($nameStart, $i - $nameStart).Trim()
      if (-not $fname) { throw "Missing filter name after '|'." }

      # read 0..N args: each starts with ':' then arg (quoted or unquoted)
      $arguments = @()
      while ($i -lt $len) {
        while ($i -lt $len -and ($Inner[$i] -match '[ \t\r\n]')) { $i++ }
        if ($i -ge $len) { break }
        if ($Inner[$i] -eq '|') { break }
        if ($Inner[$i] -ne ':') { break }  # no more args

        $i++  # consume ':'
        # read next arg
        $arg = Read-NextArg -Text $Inner -Index ([ref]$i)
        if ($arg -eq "") {
          throw "Empty filter argument for filter '$fname'."
        }
        $arguments += $arg
      }

      $pipeline += [pscustomobject]@{ Name = $fname; Args = $arguments }
      continue
    }

    # trailing spaces after last filter
    if ($Inner[$i] -match '[ \t\r\n]') {
      $i++
      continue
    }

    # anything else at this point is unexpected
    throw "Unexpected token near '$($Inner.Substring($i,[Math]::Min(12,$len-$i)))' in filter pipeline."
  }

  [pscustomobject]@{
    Head     = $head
    Pipeline = $pipeline
  }
}

# ---------------------------------------------------------------------------
# Helper: Parse-Placeholder
# Parses the inside of {{ ... }} into namespace, name, and filter pipeline.
# Expects "var.Name" or "env.NAME" followed by optional "| filter[: "arg"]".
# ---------------------------------------------------------------------------
function Parse-Placeholder {
  param(
    [Parameter(Mandatory)][string]$InnerText
  )
  # InnerText is everything between the braces, no braces included.
  # We only tokenize here; actual value resolution + filter application
  # remain in your existing code path.

  # Handle literal-double-braces escape (if you use a sentinel),
  # otherwise skip — this function only parses placeholders.

  $expr1 = $InnerText.Trim() -replace '\r?\n', ' ' # normalize newlines to spaces
  $expr1 = $expr1 -replace '\s*\|\s*', ' | '    # normalize pipe spacing
  Write-Debug "  Parse-Placeholder: `'$($expr1)`'"

  $trimmed = $InnerText.Trim()
  $ph = Tokenize-Pipeline -Inner $trimmed

  # quick sanity: head must be var.* or env.*
  if ($ph.Head -notmatch '^(var|env)\.') {
    throw "Invalid placeholder head '$($ph.Head)'. Use 'var.Name' or 'env.NAME'."
  }

  Write-Debug "    Head: `"$($ph.Head)`""
  foreach ($filter in $ph.Pipeline) {
    $arguments = $filter.Args -join ', '
    $arguments = ($arr = $filter.Args | ForEach-Object { "`"$_`"" }) -join ","
    Write-Debug "    Filter: $($filter.Name)($arguments)"
  }

  return $ph
}





function Resolve-HeadValue {
    param(
        [Parameter(Mandatory)] [string]    $Head,
        [Parameter(Mandatory)] [hashtable] $Variables
    )

    # var.NAME  -> from -Variables (or $script:Vars if you also keep the -Var strings there)
    if ($Head -match '^\s*var\.(.+)\s*$') {
        $name = $Matches[1]
        if ($Variables.ContainsKey($name)) {
            return $Variables[$name]
        } 
        # elseif ($script:Vars -and $script:Vars.ContainsKey($name)) {
        #     # If you keep string-based -Var pairs in $script:Vars, honor them too
        #     return $script:Vars[$name]
        # } 
        else {
            throw "Unknown variable 'var.$name'."
        }
    }

    # env.NAME -> environment variable
    if ($Head -match '^\s*env\.([A-Za-z0-9_]+)\s*$') {
        $envName = $Matches[1]
        $val = [System.Environment]::GetEnvironmentVariable($envName)
        if ($null -eq $val) {
            throw "Environment variable '$envName' is not defined."
        }
        return $val
    }

    throw "Invalid placeholder head '$Head'. Use 'var.Name' or 'env.NAME'."
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


# ========================= MAIN SCRIPT =========================

# ========================= Load inputs =========================

$tplPath = Resolve-PathSmart $Template
$tplText = Get-Content -LiteralPath $tplPath -Raw

Write-Host "`nExpanding a template file by $($MyInvocation.MyCommand.Name)..." -ForegroundColor Green
Write-Verbose "`nScript parameters:"
Write-HashTable $PSBoundParameters
Write-Verbose "  Positional:"
Write-Array $args
Write-Verbose "Var:"
Write-Array $Var
Write-Verbose "Variables:"
Write-HashTable $Variables
Write-Verbose "`nTemplate path: `n  ${tplPath}"
Write-Verbose ""

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

        # Extract the raw placeholder body (no braces), normalize whitespace for debug
        # $full   = $m.Value
        $body      = $m.Groups[1].Value
        $bodyShown = Normalize-Whitespace -Text $body

        Write-Verbose "Processing placeholder:`n  {{ $bodyShown }}"

        try {
            # 1) Parse the placeholder into Head + Pipeline (filters with args)
            $ph = Parse-Placeholder -InnerText $body

            Write-Debug ("  Parsed head   : {0}" -f $ph.Head)
            foreach ($f in $ph.Pipeline) {
                Write-Debug ("  Filter        : {0}({1})" -f $f.Name, (($f.Args -join '", "') -replace '^','"' -replace '$','"'))
            }

            # 2) Resolve head value (var./env.)
            $headValue = Resolve-HeadValue -Head $ph.Head -Variables $VARS
            if ($null -eq $headValue) {
                throw "Head '$($ph.Head)' resolved to null."
            }


            if ($Debug) {
                Write-Host "  Unfiltered value:`n  $headValue" -ForegroundColor DarkCyan
                if ($ph.Pipeline -and $ph.Pipeline.Count) {
                    $pipeDisplay = ($ph.Pipeline | ForEach-Object {
                        $n = $_.Name
                        $a = if ($_.Args) { ($_.Args -join '", "') } else { '' }
                        if ($a -ne '') { "$n(""$a"")" } else { "$n()" }
                    }) -join ' | '
                    Write-Host "  Pipeline: $pipeDisplay" -ForegroundColor DarkCyan
                } else {
                    Write-Host "  Pipeline: (none)" -ForegroundColor DarkCyan
                }
            }

            Write-Debug ("  Head value (type): {0}" -f ($headValue.GetType().FullName))

            # 3) Apply filters (pipeline returned by parser)
            $expanded = Apply-Filters -Value $headValue -Pipeline $ph.Pipeline


            if ($Debug) {
                Write-Host "  Final value:`n  $expanded" -ForegroundColor Green
            }


            # 4) Coerce to string for output
            if ($null -eq $expanded) { '' } else { [string]$expanded }
        }
        catch {
            throw "Error in placeholder '{{ $bodyShown }}': $($_.Exception.Message)"
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