function Normalize-Whitespace {
  param([string]$s)
  if ($null -eq $s) { return '' }
  # Collapse any CRLF/CR/LF and runs of whitespace to single spaces
  ($s -replace '[\r\n]+',' ') -replace '\s+',' '
}

function Read-NextArg {
  <#
    Reads the next filter argument from $Text starting at $Index (byref).
    Supports:
      - Quoted args: "..." with backslash escapes \" \\ \n \r \t \v \b \f and \xHH \uHHHH \UHHHHHHHH
      - Unquoted args: up to next ':' or '|' or '}}' (no whitespace needed)
    Returns the raw string (no surrounding quotes). Escapes are resolved for quoted args;
    unquoted args are returned literally (no escaping performed).
  #>
  param(
    [Parameter(Mandatory)] [string]$Text,
    [Parameter(Mandatory)] [ref]$Index
  )

  # skip spaces/newlines
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -match '\s') { $Index.Value++ }

  if ($Index.Value -ge $Text.Length) { return '' }

  $ch = $Text[$Index.Value]
  if ($ch -eq '"') {
    # Quoted argument with C-like escapes (\" \\ \n \r \t \v \b \f \xHH \uHHHH \UHHHHHHHH)
    $Index.Value++  # consume opening quote
    $sb = [System.Text.StringBuilder]::new()

    while ($Index.Value -lt $Text.Length) {
      $c = $Text[$Index.Value]

      if ($c -eq '"') { $Index.Value++; break }

      if ($c -eq '\') {
        $Index.Value++
        if ($Index.Value -ge $Text.Length) { break }
        $e = $Text[$Index.Value]

        switch ($e) {
          'n' { [void]$sb.Append([char]0x0A); $Index.Value++; continue }
          'r' { [void]$sb.Append([char]0x0D); $Index.Value++; continue }
          't' { [void]$sb.Append([char]0x09); $Index.Value++; continue }
          'v' { [void]$sb.Append([char]0x0B); $Index.Value++; continue }
          'b' { [void]$sb.Append([char]0x08); $Index.Value++; continue }
          'f' { [void]$sb.Append([char]0x0C); $Index.Value++; continue }
          '"' { [void]$sb.Append('"');       $Index.Value++; continue }
          '\' { [void]$sb.Append('\');       $Index.Value++; continue }
          'x' {
            $start = $Index.Value + 1
            $j = $start
            while ($j -lt $Text.Length -and $Text[$j] -match '[0-9a-fA-F]' -and ($j - $start) -lt 8) { $j++ }
            if ($j -eq $start) { throw "Invalid \x escape in quoted arg near index $($Index.Value)." }
            $hex = $Text.Substring($start, $j - $start)
            $val = [Convert]::ToInt32($hex,16)
            if ($val -le 0xFFFF) { [void]$sb.Append([char]$val) }
            else {
              $v  = $val - 0x10000
              $hi = 0xD800 + (($v -band 0xFFC00) -shr 10)
              $lo = 0xDC00 + ($v -band 0x3FF)
              [void]$sb.Append([char]$hi); [void]$sb.Append([char]$lo)
            }
            $Index.Value = $j
            continue
          }
          'u' {
            if ($Index.Value + 4 -ge $Text.Length) { throw "Invalid \u escape in quoted arg near index $($Index.Value)." }
            $hex = $Text.Substring($Index.Value + 1, 4)
            $val = [Convert]::ToInt32($hex,16)
            if ($val -le 0xFFFF) { [void]$sb.Append([char]$val) } else {
              $v  = $val - 0x10000
              $hi = 0xD800 + (($v -band 0xFFC00) -shr 10)
              $lo = 0xDC00 + ($v -band 0x3FF)
              [void]$sb.Append([char]$hi); [void]$sb.Append([char]$lo)
            }
            $Index.Value += 5
            continue
          }
          'U' {
            if ($Index.Value + 8 -ge $Text.Length) { throw "Invalid \U escape in quoted arg near index $($Index.Value)." }
            $hex = $Text.Substring($Index.Value + 1, 8)
            $val = [Convert]::ToInt32($hex,16)
            if ($val -le 0xFFFF) { [void]$sb.Append([char]$val) } else {
              $v  = $val - 0x10000
              $hi = 0xD800 + (($v -band 0xFFC00) -shr 10)
              $lo = 0xDC00 + ($v -band 0x3FF)
              [void]$sb.Append([char]$hi); [void]$sb.Append([char]$lo)
            }
            $Index.Value += 9
            continue
          }
          default {
            # Unknown escape — keep the character as-is (treat '\X' -> 'X')
            [void]$sb.Append($e)
            $Index.Value++
            continue
          }
        }
      }
      else {
        [void]$sb.Append($c)
        $Index.Value++
      }
    }

    return $sb.ToString()
  }
  else {
    # Unquoted: read until ':' or '|' or '}}'
    $start = $Index.Value
    while ($Index.Value -lt $Text.Length) {
      $c = $Text[$Index.Value]
      if ($c -eq ':' -or $c -eq '|' -or ($c -eq '}' -and $Index.Value + 1 -lt $Text.Length -and $Text[$Index.Value+1] -eq '}')) { break }
      $Index.Value++
    }
    return $Text.Substring($start, $Index.Value - $start).Trim()
  }
}

function Parse-Placeholder {
  <#
    Parses a single placeholder body (no outer {{ }}) into:
      .Head     — 'var.Name' or 'env.NAME'
      .Pipeline — array of [pscustomobject] @{ Name='filter'; Args=@('a','b',...) }
    Consumes characters from $Index (byref) in the provided $Text which still includes the closing '}}'.
  #>
  param(
    [Parameter(Mandatory)] [string]$Text,
    [Parameter(Mandatory)] [ref]$Index
  )

  # normalize leading whitespace
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -match '\s') { $Index.Value++ }
  if ($Index.Value -ge $Text.Length) { throw "Empty placeholder." }

  # Read head token (env.NAME or var.Name)
  $headStart = $Index.Value
  while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -notin @('|','}')) { $Index.Value++ }
  $rawHead = $Text.Substring($headStart, $Index.Value - $headStart).Trim()
  if ($rawHead -notmatch '^(env\.[A-Za-z0-9_]+|var\.[A-Za-z0-9_\.]+)$') {
    throw "Invalid placeholder head '$rawHead'. Use 'var.Name' or 'env.NAME'."
  }

  $pipeline = New-Object System.Collections.Generic.List[object]

  # zero or more: '|' filterName ( ':' arg )*
  while ($Index.Value -lt $Text.Length) {
    # skip spaces
    while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -match '\s') { $Index.Value++ }
    if ($Index.Value -ge $Text.Length) { break }

    # stop if end '}}' is next
    if ($Text[$Index.Value] -eq '}' -and $Index.Value + 1 -lt $Text.Length -and $Text[$Index.Value+1] -eq '}') {
      break
    }

    if ($Text[$Index.Value] -ne '|') {
      throw "Expected '|' or '}}' near index $($Index.Value), found '$($Text[$Index.Value])'."
    }
    $Index.Value++  # consume '|'

    # skip spaces
    while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -match '\s') { $Index.Value++ }
    if ($Index.Value -ge $Text.Length) { throw "Unexpected end after '|'." }

    # read filter name
    $nameStart = $Index.Value
    while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -match '[A-Za-z0-9_]') { $Index.Value++ }
    $filterName = $Text.Substring($nameStart, $Index.Value - $nameStart)
    if ([string]::IsNullOrEmpty($filterName)) {
      throw "Missing filter name after '|' near index $nameStart."
    }

    # read zero or more ':arg'
    $args = New-Object System.Collections.Generic.List[string]
    while ($Index.Value -lt $Text.Length) {
      # skip spaces
      while ($Index.Value -lt $Text.Length -and $Text[$Index.Value] -match '\s') { $Index.Value++ }
      if ($Index.Value -ge $Text.Length) { break }

      # end or next filter?
      if ($Text[$Index.Value] -eq '|' -or ($Text[$Index.Value] -eq '}' -and $Index.Value + 1 -lt $Text.Length -and $Text[$Index.Value+1] -eq '}')) {
        break
      }

      if ($Text[$Index.Value] -ne ':') { throw "Expected ':' or '|' or '}}' near index $($Index.Value)." }
      $Index.Value++  # consume ':'

      $arg = Read-NextArg -Text $Text -Index ([ref]$Index.Value)
      $args.Add($arg) | Out-Null
    }

    $pipeline.Add([pscustomobject]@{ Name = $filterName; Args = $args.ToArray() }) | Out-Null
  }

  return [pscustomobject]@{
    Head     = $rawHead
    Pipeline = $pipeline.ToArray()
  }
}
