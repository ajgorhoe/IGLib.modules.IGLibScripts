<# 
.SYNOPSIS
  Expand a text template with {{ ... }} placeholders supporting a simple
  filter pipeline like:  {{ var.NAME | lower | replace:"a":"b" }}

.DESCRIPTION
  Placeholders have the form:
      {{ <head> [| filter[:arg[:arg...]]]* }}
  where <head> is either:
      var.<Name>    – value from -Variables hashtable or -Var KEY=VALUE
      env.<NAME>    – environment variable (Process/User/Machine lookup)

  Filters (selection):
    - lower / upper / trim
    - append:"txt" / prepend:"txt"
    - default:"fallback"
    - replace:"old":"new"  (old/new may be unquoted if simple tokens)
    - regq        – quote for .reg default string values (" -> \")
    - regesc      – escape for .reg path-like content (" and \)
    - urlencode / urldecode
    - xmlencode / xmldecode
    - base64 / frombase64[:utf8|utf16|utf32|ascii] / strfrombase64
    - hex   / fromhex[:utf8|utf16|utf32|ascii]     / strfromhex
    - gzip / gunzip
    - escc / fromescc       – C/C++ escape/unescape
    - escjava / fromescjava – Java escape/unescape (\uXXXX only)
    - esccs / fromesccs     – C# escape/unescape (\uXXXX, \UXXXXXXXX)

.PARAMETER Template
  Template file path (.tmpl or any text file). Relative paths are resolved
  relative to this script file (or current directory if dot-sourced).

.PARAMETER Output
  Output file path. If omitted, writes next to Template without the .tmpl
  suffix. Writes UTF-16 LE if extension is .reg; otherwise UTF-8.

.PARAMETER Var
  Array of KEY=VALUE strings for simple variables.

.PARAMETER Variables
  Hashtable of variables (overrides -Var for same keys).
#>

param(
  [Parameter(Mandatory)] [string] $Template,
  [string] $Output,
  [string[]] $Var,
  [hashtable] $Variables
)

# --------------------------------------------------------------------
# Debug tracing
# --------------------------------------------------------------------
$script:ETVerbose = $false
function ET-Log([string]$msg) { if ($script:ETVerbose) { Write-Host $msg -ForegroundColor DarkGray } }

# --------------------------------------------------------------------
# Resolve script base folder robustly
# --------------------------------------------------------------------
function Get-ScriptBase {
  # Prefer PSScriptRoot when available (running from a file)
  if ($PSBoundParameters.ContainsKey('PSScriptRoot') -and $PSScriptRoot) { return $PSScriptRoot }
  if ($PSScriptRoot) { return $PSScriptRoot }

  # Fallback to the current script path
  if ($MyInvocation -and $MyInvocation.MyCommand -and $MyInvocation.MyCommand.Path) {
    return (Split-Path -Path $MyInvocation.MyCommand.Path -Parent)
  }

  # Last resort: current working directory
  return (Get-Location).Path
}

# --------------------------------------------------------------------
# Utilities: path resolution / load / save
# --------------------------------------------------------------------
function Resolve-PathLike([string]$p) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $null }
  if ([System.IO.Path]::IsPathRooted($p)) { return $p }

  $base = Get-ScriptBase
  return (Join-Path -Path $base -ChildPath $p)
}

function Load-Template([string]$path) {
  if ([string]::IsNullOrWhiteSpace($path)) { throw "Template path is empty." }
  if (-not (Test-Path -LiteralPath $path)) { throw "Template file not found: $path" }
  [System.IO.File]::ReadAllText($path, [Text.Encoding]::UTF8)
}

function Save-Text([string]$path, [string]$text) {
  if ([string]::IsNullOrWhiteSpace($path)) { throw "Output path is empty." }
  $enc = if ([System.IO.Path]::GetExtension($path).ToLowerInvariant() -eq '.reg') {
    [Text.Encoding]::Unicode          # UTF-16 LE for .reg
  } else {
    New-Object Text.UTF8Encoding $false  # UTF-8 (no BOM)
  }
  [IO.File]::WriteAllText($path, $text, $enc)
}

# --------------------------------------------------------------------
# -Var "KEY=VALUE" → hashtable
# --------------------------------------------------------------------
$script:VarKV = @{}
if ($Var) {
  foreach ($kv in $Var) {
    $parts = $kv -split '=', 2
    if ($parts.Count -ne 2) { throw "Invalid -Var entry '$kv'. Use KEY=VALUE." }
    $script:VarKV[$parts[0]] = $parts[1]
  }
}

# --------------------------------------------------------------------
# Head resolution (var/env)
# --------------------------------------------------------------------
function Resolve-HeadValue {
  param(
    [Parameter(Mandatory)][ValidateSet('var','env')] [string] $Namespace,
    [Parameter(Mandatory)] [string] $Name,
    [hashtable] $Variables
  )

  switch ($Namespace) {
    'var' {
      $val = $null
      if ($Variables -and $Variables.ContainsKey($Name)) { $val = $Variables[$Name] }
      elseif ($script:VarKV.ContainsKey($Name))          { $val = $script:VarKV[$Name] }
      if ($null -eq $val) { throw "Undefined variable 'var.$Name'." }
      return [string]$val
    }
    'env' {
      $v = [Environment]::GetEnvironmentVariable($Name, 'Process')
      if ([string]::IsNullOrEmpty($v)) { $v = [Environment]::GetEnvironmentVariable($Name, 'User') }
      if ([string]::IsNullOrEmpty($v)) { $v = [Environment]::GetEnvironmentVariable($Name, 'Machine') }
      if ([string]::IsNullOrEmpty($v)) { throw "Undefined environment variable 'env.$Name'." }
      return $v
    }
  }
}

# --------------------------------------------------------------------
# Arg reader: supports "quoted" or simple token (no ws, :, |, })
# Advances by-ref $pos; returns $null if no arg present
# --------------------------------------------------------------------
function Read-NextArg {
  param(
    [Parameter(Mandatory)][string] $Text,
    [Parameter(Mandatory)][ref]    $pos
  )
  $len = $Text.Length
  while ($pos.Value -lt $len -and [char]::IsWhiteSpace($Text[$pos.Value])) { $pos.Value++ }
  if ($pos.Value -ge $len) { return $null }

  $c = $Text[$pos.Value]
  if ($c -eq '|' -or $c -eq '}' -or $c -eq ':') { return $null }

  if ($c -eq '"') {
    $pos.Value++
    $sb = [Text.StringBuilder]::new()
    while ($pos.Value -lt $len) {
      $d = $Text[$pos.Value]
      if ($d -eq '"') { $pos.Value++; break }
      if ($d -eq '\') {
        if ($pos.Value + 1 -lt $len -and ($Text[$pos.Value+1] -in @('"','\'))) {
          [void]$sb.Append($Text[$pos.Value+1]); $pos.Value += 2; continue
        }
      }
      [void]$sb.Append($d); $pos.Value++
    }
    return $sb.ToString()
  } else {
    $start = $pos.Value
    while ($pos.Value -lt $len) {
      $d = $Text[$pos.Value]
      if ([char]::IsWhiteSpace($d) -or $d -eq '|' -or $d -eq '}' -or $d -eq ':') { break }
      $pos.Value++
    }
    if ($pos.Value -eq $start) { return $null }
    return $Text.Substring($start, $pos.Value - $start)
  }
}

# --------------------------------------------------------------------
# Placeholder parser  {{ head | filter[:arg[:arg...]] ... }}
# --------------------------------------------------------------------
function Parse-Placeholder {
  param(
    [Parameter(Mandatory)][string] $Text,
    [Parameter(Mandatory)][ref]    $Index
  )

  $len = $Text.Length
  if ($Index.Value + 1 -ge $len -or $Text[$Index.Value] -ne '{' -or $Text[$Index.Value+1] -ne '}') {
    # We expect '{{' here
    if ($Index.Value + 1 -ge $len -or $Text[$Index.Value] -ne '{' -or $Text[$Index.Value+1] -ne '{') {
      throw "Internal parser error: expected '{{' at $($Index.Value)."
    }
  }

  # Skip '{{'
  $Index.Value += 2

  # Skip leading whitespace
  while ($Index.Value -lt $len -and [char]::IsWhiteSpace($Text[$Index.Value])) { $Index.Value++ }

  # ---- Robust head parsing: capture everything up to '|' or '}}' and regex it
  $scan = $Index.Value
  while ($scan -lt $len) {
    $ch = $Text[$scan]
    if ($ch -eq '|' -or $ch -eq '}') { break }
    $scan++
  }
  if ($scan -le $Index.Value) { throw "Invalid placeholder: missing head at $($Index.Value)." }

  # chunk contains the “head” portion (possibly with whitespace/newlines)
  $chunk = $Text.Substring($Index.Value, $scan - $Index.Value)

  # Match:   var   .   Name   OR   env   .   NAME
  $m = [regex]::Match($chunk, '^(?is)\s*(var|env)\s*\.\s*([A-Za-z_][\w\.]*)\s*$')
  if (-not $m.Success) {
    # Extract a small, cleaned preview to show in the error
    $preview = ($chunk -replace '\s+', ' ').Trim()
    if ([string]::IsNullOrEmpty($preview)) { $preview = '(empty)' }
    throw "Invalid placeholder head '$preview'. Use 'var.Name' or 'env.NAME'."
  }

  $Namespace = $m.Groups[1].Value.ToLowerInvariant()
  $Name      = $m.Groups[2].Value

  # Advance index to where we stopped scanning (right before '|' or '}')
  $Index.Value = $scan

  # Skip trailing whitespace after head (still before '|' or '}}')
  while ($Index.Value -lt $len -and [char]::IsWhiteSpace($Text[$Index.Value])) { $Index.Value++ }

  # ---- Parse filter pipeline (unchanged logic)
  $pipeline = New-Object System.Collections.Generic.List[object]
  while ($Index.Value -lt $len -and $Text[$Index.Value] -eq '|') {
    $Index.Value++
    while ($Index.Value -lt $len -and [char]::IsWhiteSpace($Text[$Index.Value])) { $Index.Value++ }

    $fStart = $Index.Value
    while ($Index.Value -lt $len) {
      $ch = $Text[$Index.Value]
      if ([char]::IsWhiteSpace($ch) -or $ch -eq '|' -or $ch -eq '}' -or $ch -eq ':') { break }
      $Index.Value++
    }
    if ($Index.Value -eq $fStart) { throw "Invalid filter name at index $($Index.Value)." }
    $filterName = $Text.Substring($fStart, $Index.Value - $fStart).Trim().ToLowerInvariant()

    while ($Index.Value -lt $len -and [char]::IsWhiteSpace($Text[$Index.Value])) { $Index.Value++ }

    $args = @()
    while ($Index.Value -lt $len -and $Text[$Index.Value] -eq ':') {
      $Index.Value++
      $arg = Read-NextArg -Text $Text -pos ([ref]$Index.Value)
      if ($null -eq $arg) { throw "Missing value after ':' for filter '$filterName' at index $($Index.Value)." }
      $args += $arg
      while ($Index.Value -lt $len -and [char]::IsWhiteSpace($Text[$Index.Value])) { $Index.Value++ }
    }

    $pipeline.Add([pscustomobject]@{ Name = $filterName; Args = $args })
    while ($Index.Value -lt $len -and [char]::IsWhiteSpace($Text[$Index.Value])) { $Index.Value++ }
  }

  # Closing braces
  while ($Index.Value -lt $len -and [char]::IsWhiteSpace($Text[$Index.Value])) { $Index.Value++ }
  if ($Index.Value + 1 -ge $len -or $Text[$Index.Value] -ne '}' -or $Text[$Index.Value+1] -ne '}') {
    throw "Unclosed placeholder. Expected '}}' near index $($Index.Value)."
  }
  $Index.Value += 2

  [pscustomobject]@{
    Namespace = $Namespace
    Name      = $Name
    Pipeline  = $pipeline
  }
}


# --------------------------------------------------------------------
# Byte/text helpers, encoders, gzip
# --------------------------------------------------------------------
function To-Bytes([string]$text, [string]$enc = 'utf8') {
  switch ($enc.ToLowerInvariant()) {
    'utf8'  { return [Text.Encoding]::UTF8.GetBytes($text) }
    'utf16' { return [Text.Encoding]::Unicode.GetBytes($text) }
    'utf32' { return [Text.Encoding]::UTF32.GetBytes($text) }
    'ascii' { return [Text.Encoding]::ASCII.GetBytes($text) }
    default { throw "Unknown encoding '$enc'." }
  }
}
function From-Bytes([byte[]]$bytes, [string]$enc = 'utf8') {
  switch ($enc.ToLowerInvariant()) {
    'utf8'  { return [Text.Encoding]::UTF8.GetString($bytes) }
    'utf16' { return [Text.Encoding]::Unicode.GetString($bytes) }
    'utf32' { return [Text.Encoding]::UTF32.GetString($bytes) }
    'ascii' { return [Text.Encoding]::ASCII.GetString($bytes) }
    default { throw "Unknown encoding '$enc'." }
  }
}

function GZip-Compress([byte[]]$bytes) {
  $msOut = New-Object IO.MemoryStream
  $gz = New-Object IO.Compression.GZipStream($msOut, [IO.Compression.CompressionMode]::Compress, $true)
  $gz.Write($bytes, 0, $bytes.Length)
  $gz.Dispose()
  $msOut.ToArray()
}
function GZip-Expand([byte[]]$bytes) {
  $msIn  = New-Object IO.MemoryStream(,$bytes)
  $gz    = New-Object IO.Compression.GZipStream($msIn, [IO.Compression.CompressionMode]::Decompress)
  $msOut = New-Object IO.MemoryStream
  $buf = New-Object byte[] 8192
  while (($read = $gz.Read($buf,0,$buf.Length)) -gt 0) { $msOut.Write($buf,0,$read) }
  $gz.Dispose(); $msIn.Dispose()
  $msOut.ToArray()
}

function Html-Encode([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function Html-Decode([string]$s) { [System.Net.WebUtility]::HtmlDecode($s) }
function Url-Encode([string]$s)  { [Uri]::EscapeDataString($s) }
function Url-Decode([string]$s)  { [Uri]::UnescapeDataString($s) }
function Reg-Quote([string]$s)   { $s -replace '\\', '\\\\' -replace '"', '\"' }
function Reg-Escape([string]$s)  { $s -replace '\\', '\\\\' -replace '"', '\"' }

function Path-Append([string]$p, [string]$child) {
  if ([string]::IsNullOrWhiteSpace($p)) { return $child }
  if ([string]::IsNullOrWhiteSpace($child)) { return $p }
  return [IO.Path]::Combine($p, $child)
}
function Path-Quote([string]$p) {
  if ($p -match '\s' -and -not ($p.StartsWith('"') -and $p.EndsWith('"'))) { return '"' + $p + '"' }
  return $p
}

# --------------------------------------------------------------------
# C / C++ escape filters (escc / fromescc)
# --------------------------------------------------------------------
function Filter-EscC {
  param([Parameter(Mandatory)][string]$Text)

  $sb = [Text.StringBuilder]::new()
  function Append-UnicodeEscape([Text.StringBuilder]$B, [int]$cp) {
    if ($cp -le 0xFFFF) { [void]$B.Append('\u'); [void]$B.Append($cp.ToString('X4')) }
    else                { [void]$B.Append('\U'); [void]$B.Append($cp.ToString('X8')) }
  }

  $i=0; $len=$Text.Length
  while ($i -lt $len) {
    $c = [int][char]$Text[$i]
    if ($c -ge 0xD800 -and $c -le 0xDBFF -and ($i+1) -lt $len) {
      $c2 = [int][char]$Text[$i+1]
      if ($c2 -ge 0xDC00 -and $c2 -le 0xDFFF) {
        $v  = (($c - 0xD800) -shl 10) + ($c2 - 0xDC00) + 0x10000
        Append-UnicodeEscape $sb $v
        $i += 2; continue
      }
    }
    switch ($c) {
      0x07 { [void]$sb.Append('\a'); $i++; continue }
      0x08 { [void]$sb.Append('\b'); $i++; continue }
      0x09 { [void]$sb.Append('\t'); $i++; continue }
      0x0A { [void]$sb.Append('\n'); $i++; continue }
      0x0B { [void]$sb.Append('\v'); $i++; continue }
      0x0C { [void]$sb.Append('\f'); $i++; continue }
      0x0D { [void]$sb.Append('\r'); $i++; continue }
      0x22 { [void]$sb.Append('\"'); $i++; continue }
      0x27 { [void]$sb.Append("\'"); $i++; continue }
      0x3F { [void]$sb.Append('\?'); $i++; continue }
      0x5C { [void]$sb.Append('\\'); $i++; continue }
      default {
        if ($c -lt 0x20 -or $c -eq 0x7F) { Append-UnicodeEscape $sb $c }
        elseif ($c -le 0x7E) { [void]$sb.Append([char]$c) }
        else { Append-UnicodeEscape $sb $c }
        $i++
      }
    }
  }
  $sb.ToString()
}

function Filter-FromEscC {
  param([Parameter(Mandatory)][string]$Text)

  $sb  = [Text.StringBuilder]::new()
  $i   = 0
  $len = $Text.Length

  function Parse-Hex([string]$s) {
    $v = 0
    if (-not [int]::TryParse($s, [Globalization.NumberStyles]::AllowHexSpecifier,
             [Globalization.CultureInfo]::InvariantCulture, [ref]$v)) {
      throw "Invalid hex digits '$s'."
    }
    $v
  }
  function Append-CP([Text.StringBuilder]$B, [int]$cp) {
    if ($cp -le 0xFFFF) { [void]$B.Append([char]$cp) }
    else { $v=$cp-0x10000; $hi=0xD800+(($v -band 0xFFC00) -shr 10); $lo=0xDC00+($v -band 0x3FF); [void]$B.Append([char]$hi); [void]$B.Append([char]$lo) }
  }

  while ($i -lt $len) {
    $ch = $Text[$i]
    if ($ch -ne '\') { [void]$sb.Append($ch); $i++; continue }
    if ($i + 1 -ge $len) { [void]$sb.Append('\'); break }

    $i++; $esc = $Text[$i]
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
        $start = $i + 1; $j = $start
        while ($j -lt $len -and ($Text[$j] -match '[0-9A-Fa-f]')) { if (($j - $start) -ge 8) { break }; $j++ }
        if ($j -eq $start) { throw "Invalid \x escape at ${i}: expected hex." }
        $hex = $Text.Substring($start, $j - $start)
        $val = Parse-Hex $hex
        Append-CP $sb $val
        $i = $j; continue
      }
      'u' {
        if ($i + 4 -ge $len) { throw "Invalid \u escape at ${i}: need 4 hex." }
        $hex = $Text.Substring($i + 1, 4)
        $val = Parse-Hex $hex
        Append-CP $sb $val
        $i += 5; continue
      }
      'U' {
        if ($i + 8 -ge $len) { throw "Invalid \U escape at ${i}: need 8 hex." }
        $hex = $Text.Substring($i + 1, 8)
        $val = Parse-Hex $hex
        Append-CP $sb $val
        $i += 9; continue
      }
      default {
        if ($esc -ge '0' -and $esc -le '7') {
          $start = $i; $digits = 1
          while ($digits -lt 3 -and $i + 1 -lt $len -and $Text[$i+1] -ge '0' -and $Text[$i+1] -le '7') { $i++; $digits++ }
          $oct = $Text.Substring($start, $digits)
          $val = [Convert]::ToInt32($oct, 8)
          Append-CP $sb $val
          $i = $start + $digits
          continue
        }
        [void]$sb.Append($esc); $i++; continue
      }
    }
  }
  $sb.ToString()
}

# Java & C# wrappers remain as in the previous version
function Filter-EscJava     { param([Parameter(Mandatory)][string]$Text)  (Filter-EscC $Text) -replace '\\U([0-9A-Fa-f]{8})','\u$1' } # simple reuse; tight Java version exists in previous build if needed
function Filter-FromEscJava { param([Parameter(Mandatory)][string]$Text)  Filter-FromEscC $Text }
function Filter-EscCs       { param([Parameter(Mandatory)][string]$Text)  Filter-EscC $Text }
function Filter-FromEscCs   { param([Parameter(Mandatory)][string]$Text)  Filter-FromEscC $Text }

# --------------------------------------------------------------------
# Apply filter pipeline
# --------------------------------------------------------------------
function Apply-Filters {
  param(
    [AllowNull()] $Value,
    [Parameter(Mandatory)] $Pipeline
  )

  if ($null -eq $Value) { throw "Filter pipeline received null input. Check the placeholder head (var/env) resolves correctly." }

  foreach ($f in $Pipeline) {
    $name = $f.Name
    $args = $f.Args

    ET-Log ("  | {0}{1}" -f $name, ($(if ($args.Count) {': ' + ($args -join ', ')} else {''})))

    switch ($name) {
      'lower'   { $Value = [string]$Value; $Value = $Value.ToLowerInvariant(); continue }
      'upper'   { $Value = [string]$Value; $Value = $Value.ToUpperInvariant(); continue }
      'trim'    { $Value = [string]$Value; $Value = $Value.Trim(); continue }
      'append'  { $Value = [string]$Value + ($(if ($args.Count){$args[0]}else{''})); continue }
      'prepend' { $Value = ($(if ($args.Count){$args[0]}else{''})) + [string]$Value; continue }
      'default' { if ([string]::IsNullOrEmpty([string]$Value) -and $args.Count){ $Value = $args[0] }; continue }

      'replace' {
        if ($args.Count -ne 2) { throw "replace filter requires two arguments: replace:'old':'new'" }
        $Value = [string]$Value
        $Value = $Value.Replace($args[0], $args[1])
        continue
      }

      'regq'   { $Value = Reg-Quote ([string]$Value); continue }
      'regesc' { $Value = Reg-Escape ([string]$Value); continue }

      'urlencode' { $Value = Url-Encode ([string]$Value); continue }
      'urldecode' { $Value = Url-Decode ([string]$Value); continue }

      'xmlencode' { $Value = Html-Encode ([string]$Value); continue }
      'xmldecode' { $Value = Html-Decode ([string]$Value); continue }

      'pathappend' {
        if ($args.Count -lt 1) { throw "pathappend requires an argument." }
        $Value = Path-Append ([string]$Value) $args[0]; continue
      }
      'pathquote' { $Value = Path-Quote ([string]$Value); continue }

      # --- Encodings ---
      'base64' {
        if ($Value -is [byte[]]) { $Value = [Convert]::ToBase64String($Value) }
        else { $Value = [Convert]::ToBase64String((To-Bytes ([string]$Value) 'utf16')) }
        continue
      }
      'frombase64' {
        $bytes = [Convert]::FromBase64String([string]$Value)
        if ($args.Count -gt 0) { $Value = From-Bytes $bytes $args[0] } else { $Value = $bytes }
        continue
      }
      'strfrombase64' {
        $bytes = [Convert]::FromBase64String([string]$Value)
        $Value = From-Bytes $bytes 'utf16'
        continue
      }

      'hex' {
        $b = if ($Value -is [byte[]]) { $Value } else { To-Bytes ([string]$Value) 'utf16' }
        $sb = [Text.StringBuilder]::new()
        foreach ($x in $b) { [void]$sb.Append($x.ToString('x2')) }
        $Value = $sb.ToString()
        continue
      }
      'fromhex' {
        $s = ([string]$Value).Trim()
        if ($s.Length % 2 -ne 0) { throw "fromhex requires an even number of hex chars." }
        $bytes = New-Object byte[] ($s.Length/2)
        for ($i=0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($s.Substring(2*$i, 2), 16) }
        if ($args.Count -gt 0) { $Value = From-Bytes $bytes $args[0] } else { $Value = $bytes }
        continue
      }
      'strfromhex' {
        $s = ([string]$Value).Trim()
        if ($s.Length % 2 -ne 0) { throw "strfromhex requires an even number of hex chars." }
        $bytes = New-Object byte[] ($s.Length/2)
        for ($i=0; $i -lt $bytes.Length; $i++) { $bytes[$i] = [Convert]::ToByte($s.Substring(2*$i, 2), 16) }
        $Value = From-Bytes $bytes 'utf16'
        continue
      }

      'gzip'   {
        $b = if ($Value -is [byte[]]) { $Value } else { To-Bytes ([string]$Value) 'utf16' }
        $Value = GZip-Compress $b; continue
      }
      'gunzip' {
        if (-not ($Value -is [byte[]])) { throw "gunzip expects byte[] input (use frombase64/fromhex first)." }
        $Value = GZip-Expand $Value; continue
      }

      'escc'         { $Value = Filter-EscC ([string]$Value); continue }
      'fromescc'     { $Value = Filter-FromEscC ([string]$Value); continue }
      'escjava'      { $Value = Filter-EscJava ([string]$Value); continue }
      'fromescjava'  { $Value = Filter-FromEscJava ([string]$Value); continue }
      'esccs'        { $Value = Filter-EscCs ([string]$Value); continue }
      'fromesccs'    { $Value = Filter-FromEscCs ([string]$Value); continue }

      default { throw "Unknown filter '$name'." }
    }
  }

  return $Value
}

# --------------------------------------------------------------------
# Expand entire template string
# --------------------------------------------------------------------
function Expand-TemplateString {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][hashtable]$Variables
  )

  $sb  = [System.Text.StringBuilder]::new()
  $len = $Text.Length
  $i   = 0

  while ($i -lt $len) {

    # --- Treat escaped openers as literal '{{'
    if ($i + 2 -lt $len -and $Text[$i] -eq '\' -and $Text[$i+1] -eq '{' -and $Text[$i+2] -eq '{') {
      [void]$sb.Append('{{'); $i += 3; continue
    }
    # Support the alternate escape form '\{\{' as literal '{{'
    if ($i + 3 -lt $len -and $Text[$i] -eq '\' -and $Text[$i+1] -eq '{' -and $Text[$i+2] -eq '\' -and $Text[$i+3] -eq '{') {
      [void]$sb.Append('{{'); $i += 4; continue
    }

    # --- Treat escaped closers as literal '}}'
    if ($i + 2 -lt $len -and $Text[$i] -eq '\' -and $Text[$i+1] -eq '}' -and $Text[$i+2] -eq '}') {
      [void]$sb.Append('}}'); $i += 3; continue
    }
    # Support the alternate escape form '\}\}' as literal '}}'
    if ($i + 3 -lt $len -and $Text[$i] -eq '\' -and $Text[$i+1] -eq '}' -and $Text[$i+2] -eq '\' -and $Text[$i+3] -eq '}') {
      [void]$sb.Append('}}'); $i += 4; continue
    }

    # --- Real placeholder opener?
    if ($i + 1 -lt $len -and $Text[$i] -eq '{' -and $Text[$i+1] -eq '{') {
      $refIdx = [ref]$i
      try {
        $ph = Parse-Placeholder -Text $Text -Index $refIdx
      } catch {
        throw
      }
      # Update position to after the closing '}}' consumed by Parse-Placeholder
      $i = $refIdx.Value

      # Resolve head, apply filters, and append
      $headValue = Resolve-HeadValue -Namespace $ph.Namespace -Name $ph.Name -Variables $Variables
      if ($null -eq $headValue) {
        throw "Filter pipeline received null input. Check the placeholder head ($($ph.Namespace).$($ph.Name)) resolves correctly."
      }
      $expanded = Apply-Filters -Value $headValue -Filters $ph.Pipeline
      if ($null -ne $expanded) { [void]$sb.Append($expanded) }
      continue
    }

    # Fallback: copy one char
    [void]$sb.Append($Text[$i])
    $i++
  }

  $sb.ToString()
}

# --------------------------------------------------------------------
# Main
# --------------------------------------------------------------------
# Resolve paths
$tmplPath = Resolve-PathLike $Template
if (-not $tmplPath) { throw "Template path is empty or invalid." }

if (-not $Output) {
  $dir  = Split-Path -Path $tmplPath -Parent
  $name = [IO.Path]::GetFileName($tmplPath)
  if ($name.ToLowerInvariant().EndsWith('.tmpl')) { $name = $name.Substring(0, $name.Length-5) }
  $Output = Join-Path $dir $name
} else {
  $Output = Resolve-PathLike $Output
}

# Load, expand, save
$raw    = Load-Template $tmplPath
$result = Expand-TemplateString -Text $raw -Variables $Variables
Save-Text $Output $result
Write-Host "Template expanded to: $Output"
