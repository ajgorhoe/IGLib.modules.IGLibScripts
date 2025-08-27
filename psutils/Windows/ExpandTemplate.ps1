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
    param($v)
    $s = As-String $v
    return [System.Convert]::FromBase64String($s)
}

# ========================= Hex (lowercase) =========================
function Filter-Hex {
    param($v)
    $bytes = As-Bytes $v
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}
function Filter-FromHex {
    param($v)
    $s = (As-String $v) -replace '\s',''
    if ($s.Length % 2 -ne 0) { throw "fromhex requires an even number of hex digits." }
    $len = $s.Length / 2
    $bytes = New-Object byte[] $len
    for ($i=0; $i -lt $len; $i++) {
        $bytes[$i] = [Convert]::ToByte($s.Substring(2*$i,2),16)
    }
    return $bytes
}

# ========================= GZip =========================
function Filter-Gzip {
    param($v)
    $in = As-Bytes $v
    $msOut = New-Object System.IO.MemoryStream
    $gzip = New-Object System.IO.Compression.GzipStream($msOut, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $gzip.Write($in, 0, $in.Length)
    $gzip.Dispose()
    return $msOut.ToArray()
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
    # Return TEXT (Unicode) by default
    return [System.Text.Encoding]::Unicode.GetString($outBytes)
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

# ========================= C-style escape/unescape =========================
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

# ========================= Java/C# variants =========================
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

function Convert-CodePointToString {
    param([int]$cp)
    if ($cp -le 0xFFFF) { return [char]$cp }
    $cp -= 0x10000
    $hi = 0xD800 + ($cp -shr 10)
    $lo = 0xDC00 + ($cp -band 0x3FF)
    return ([char]$hi).ToString() + ([char]$lo)
}
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
            'pathappend' { 
              $Value = $Value + ($(if ($null -ne $arg) { $arg } else { '' })) 
            }
            'pathquote'  {
                # Quote only if not already quoted (tolerates surrounding whitespace)
                if ($Value -notmatch '^\s*".*"\s*$') { $Value = '"' + $Value + '"' }
            }
            'pathwin' { $Value = To-WindowsPathPreserveRelative $Value }
            'pathlinux' { $Value = To-LinuxPathPreserveRelative $Value }
            'pathos' { $Value = To-OSPathPreserveRelative $Value }
            'pathwinabs' { $Value = To-WindowsPathAbsolute $Value }
            'pathlinuxabs' { $Value = To-LinuxPathAbsolute $Value }
            'pathosabs' { $Value = To-OSPathAbsolute $Value }
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