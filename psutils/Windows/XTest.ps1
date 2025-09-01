function Filter-FromEscC {
    <#
      .SYNOPSIS
        Decodes C/C++-style escape sequences in a string.

      .NOTES
        Supported: \\, \', \", \?, \a, \b, \f, \n, \r, \t, \v, \0 / \oo / \ooo (octal 0–3 digits),
                   \xH… (1–4 hex digits; continues up to 4).
        For \x4142 this yields a single U+4142 character (as in C).
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

        switch ($esc) {
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
                # \x followed by 1–4 hex digits (C keeps consuming while hex; we cap at 4)
                $start = $i + 1
                $len   = 0
                while ($start + $len -lt $Value.Length -and $Value[$start + $len] -match '[0-9A-Fa-f]') {
                    $len++
                    if ($len -ge 4) { break }
                }
                if ($len -eq 0) { throw "Invalid \x escape at index $($i-1): missing hex digits." }
                $hex  = $Value.Substring($start, $len)
                $code = [Convert]::ToInt32($hex, 16)
                [void]$sb.Append([char]$code)
                $i += 1 + $len
            }
            { $_ -match '[0-7]' } {
                # Octal: up to 3 digits, first already in $esc
                $start = $i
                $len   = 1
                while ($len -lt 3 -and ($start + $len) -lt $Value.Length -and $Value[$start + $len] -match '^[0-7]$') {
                    $len++
                }
                $oct  = $Value.Substring($start, $len)
                $code = [Convert]::ToInt32($oct, 8)
                [void]$sb.Append([char]$code)
                $i += $len
            }
            default {
                # Unknown escape -> keep the escaped char literally (C’s behavior is undefined; we keep it simple)
                [void]$sb.Append($esc)
                $i++
            }
        }
    }
    $sb.ToString()
}

function Filter-FromEscCs {
    <#
      .SYNOPSIS
        Decodes C#-style escape sequences in a string.

      .NOTES
        Supported: \\, \', \", \a, \b, \f, \n, \r, \t, \v, \0,
                   \xH… (1–4 hex digits),
                   \uXXXX (exactly 4 hex digits),
                   \UXXXXXXXX (exactly 8 hex digits, full Unicode code point; emits surrogate pair if needed).
        C# does NOT support octal escapes; if you have them, we treat as literal for compatibility,
        or you can enable the octal branch (commented) if you want to accept them too.
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

        switch ($esc) {
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
                # \x followed by 1–4 hex digits (C# permits 1–4)
                $start = $i + 1
                $len   = 0
                while ($start + $len -lt $Value.Length -and $Value[$start + $len] -match '[0-9A-Fa-f]') {
                    $len++
                    if ($len -ge 4) { break }
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
                # \UXXXXXXXX (exactly 8 hex digits, full Unicode code point)
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
                # C# does NOT define octal escapes; keep the escaped char literally.
                # If you want to accept octal as well (like the C decoder), you could
                # copy the octal branch from Filter-FromEscC here.
                [void]$sb.Append($esc)
                $i++
            }
        }
    }
    $sb.ToString()
}
