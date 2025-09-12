

# Console colors:
# Black, DarkBlue, DarkGreen, DarkCyan, DarkRed, DarkMagenta, 
# DarkYellow, Gray, DarkGray, Blue, Green, Cyan, Red, Magenta, Yellow, White

$script:VerboseMode = $true  # Set to $true to enable debug messages
$script:DebugMode = $true  # Set to $true to enable debug messages

$FgVerbose = "Gray" # Verbose messages color
$FgDebug = "DarkGray"  # Debug messages color

function Write-Debug {
  param([string]$Msg)
  # if ($script:DebugMode) { Write-Host "[DBG] $Msg" -ForegroundColor $FgDebug }
  if ($script:DebugMode) { Write-Host "$Msg" -ForegroundColor $FgDebug }
}

function Write-Verbose {
  param([string]$Msg)
  # if ($script:DebugMode) { Write-Host "[DBG] $Msg" -ForegroundColor $FgDebug }
  if ($script:VerboseMode) { Write-Host "$Msg" -ForegroundColor $FgVerbose }
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
      
      # if ($ch -eq '\') {
      #   if ($i + 1 -lt $len) {
      #     $n = $Text[$i+1]
      #     switch ($n) {
      #       '"'{ [void]$sb.Append('"');  $i+=2; continue }
      #       '\' { [void]$sb.Append('\'); $i+=2; continue }
      #       default { [void]$sb.Append('\'); $i++; continue }
      #     }
      #   }
      # }

      if ($ch -eq '\') {
        if ($i + 1 -lt $len) {
          $n = $Text[$i+1]
          switch ($n) {
            '"' { [void]$sb.Append('"');  $i += 2; continue }
            '\' { [void]$sb.Append('\');  $i += 2; continue }
            default {
              # Preserve unknown escapes literally, but DO NOT consume the next char yet.
              # Append the backslash and advance one; the next iteration will handle the next char.
              [void]$sb.Append('\')
              $i += 1
              continue
            }
          }
        } else {
          # Trailing backslash inside quotes; keep it
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
      $args = @()
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
        $args += $arg
      }

      $pipeline += [pscustomobject]@{ Name = $fname; Args = $args }
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

function Parse-Placeholder {
  param(
    [Parameter(Mandatory)][string]$InnerText
  )
  # InnerText is everything between the braces, no braces included.
  # We only tokenize here; actual value resolution + filter application
  # remain in your existing code path.

  # Handle your literal-double-braces escape (if you use a sentinel),
  # otherwise skip — this function only parses placeholders.
  $trimmed = $InnerText.Trim()

  $ph = Tokenize-Pipeline -Inner $trimmed

  # quick sanity: head must be var.* or env.*
  if ($ph.Head -notmatch '^(var|env)\.') {
    throw "Invalid placeholder head '$($ph.Head)'. Use 'var.Name' or 'env.NAME'."
  }

  return $ph
}




function Test-ParsePlaceholderHardcoded {
  # Simple tests for Parse-Placeholder function

  Write-Host "`nRunning Parse-Placeholder tests..." -ForegroundColor Cyan

  # 1) Unquoted args
  Write-Host "`nTest 1: Unquoted args" -ForegroundColor Yellow
  $inner = 'var.MyVarLong | replace:demonstrate:show | prepend:The | append:End'
  $ph = Parse-Placeholder $inner
  $ph.Head        # var.MyVarLong
  $ph.Pipeline    # replace('demonstrate','show'), prepend('The'), append('End')

  # 2) Mixed quoted/unquoted
  Write-Host "`nTest 2: Mixed quoted/unquoted args" -ForegroundColor Yellow
  $inner = 'var.PathWin | pathappend:"dir1\dir2\icon.png" | replace:\\:/'
  $ph = Parse-Placeholder $inner
  $ph.Head        # var.PathWin
  $ph.Pipeline    # pathappend('dir1\dir2\icon.png'), replace('\\','/')

  # 3) Spaces around tokens
  Write-Host "`nTest 3: Spaces around tokens" -ForegroundColor Yellow
  $inner = '  var.Name    |  lower   | replace  : X  :  "Y Y"  '
  $ph = Parse-Placeholder $inner
  $ph.Head        # var.Name
  $ph.Pipeline    # lower, replace('X','Y Y')

  Write-Host "`nAll tests completed.`n"
}



function Test-ParsePlaceholder {
    param(
        [string[]] $Contents
    )
    Write-Verbose "`nRunning Parse-Placeholder tests for $($Contents.Count) placeholders..."
    $i = 0
    foreach ($inner in $Contents) {
      $i++
      $numLines = ([regex]::Matches($inner, "`n")).Count + 1
      Write-Verbose "`n  Placeholder No. $i content (normalized; $numLines line(s)):"
      # Write-Verbose "    $inner"
      $expr1 = $inner.Trim() -replace '\r?\n', ' ' # normalize newlines to spaces
      $expr1 = $expr1 -replace '\s*\|\s*', ' | '    # normalize pipe spacing
      Write-Verbose "    $expr1"
      $ph = Parse-Placeholder $inner
      Write-Verbose "    Head: `"$($ph.Head)`""
      foreach ($filter in $ph.Pipeline) {
        $args = $filter.Args -join ', '
        $args = ($arr = $filter.Args | ForEach-Object { "`"$_`"" }) -join ","
        Write-Verbose "    Filter: $($filter.Name)($args)"
      }
    }
    Write-Verbose "`n ... Parse-Placeholder tests completed.`n"
}


# Test cases for Parse-Placeholder function:
$_PlaceholderContents = @(
  # 1) Unquoted args
  'var.MyVarLong | replace:demonstrate:show | prepend:The | append:End'
  ,
  # 2) Mixed quoted/unquoted
  'var.PathWin | pathappend:"dir1\dir2\icon.png" | replace:\\:/'
  ,
  # 3) Spaces around tokens
  '  var.Name    |  lower   | replace  : X  :  "Y Y"  '
  ,
  # 4) Newlines in placeholder - simple
  '  var.Name    
  |  lower '
  ,
  # 5) Newlines in placeholder - more complex
'
      var.PathWin
        | pathappend:"dir1\dir2\icon.png" | 
        replace:\\:/
        |
        prepend:"The path is: "
'
  ,
  # 6) Edge case: no filters, just head
  '  var.Simple  '
  ,
  # 7) Edge case: no spaces
  'var.PathWin|pathappend:"dir1\\dir2\\icon.png"|replace:\\:/|lower|prepend:"The path is: "'
)


# Run the tests:
Test-ParsePlaceholder $_PlaceholderContents

