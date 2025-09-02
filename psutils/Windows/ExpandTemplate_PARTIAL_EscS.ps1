
# Convert literal string to a string with C/C++-style escape sequences:
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

        # Handle surrogate pairs manually (no System.Text.Rune)
        if ($c -ge 0xD800 -and $c -le 0xDBFF -and ($i + 1) -lt $len) {
            $c2 = [int][char]$Text[$i+1]
            if ($c2 -ge 0xDC00 -and $c2 -le 0xDFFF) {
                $v  = (($c - 0xD800) -shl 10) + ($c2 - 0xDC00) + 0x10000
                # For C style we can emit \UXXXXXXXX (or leave as literal). We choose escape for portability.
                Append-UnicodeEscape $sb $v
                $i += 2
                continue
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
            0x22 { [void]$sb.Append('\"'); $i++; continue } # "
            0x27 { [void]$sb.Append("\'"); $i++; continue } # '
            0x3F { [void]$sb.Append('\?'); $i++; continue } # ?
            0x5C { [void]$sb.Append('\\'); $i++; continue } # backslash

            default {
                if ($c -lt 0x20 -or $c -eq 0x7F) {
                    # Control char -> \xHH
                    [void]$sb.Append('\x')
                    [void]$sb.Append($c.ToString('X2'))
                } elseif ($c -le 0x7E) {
                    # Printable ASCII
                    [void]$sb.Append([char]$c)
                } else {
                    # Non-ASCII BMP: \uXXXX
                    Append-UnicodeEscape $sb $c
                }
                $i++
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
