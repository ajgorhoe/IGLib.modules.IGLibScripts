
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
            # BMP
            [void]$B.Append([char]$cp)
        } else {
            # Encode surrogate pair (no System.Text.Rune needed)
            $v  = $cp - 0x10000
            $hi = 0xD800 + (($v -band 0xFFC00) -shr 10)
            $lo = 0xDC00 + ($v -band 0x3FF)
            [void]$B.Append([char]$hi)
            [void]$B.Append([char]$lo)
        }
    }

    while ($i -lt $len) {
        $ch = $Text[$i]
        if ($ch -ne '\') {
            [void]$sb.Append($ch)
            $i++; continue
        }

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
                # \xHH... : 1–8 hex digits (C allows variable length)
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
                if ($i + 4 -ge $len) { throw "Invalid \u escape at index ${i}: expected 4 hex digits." }
                $hex = $Text.Substring($i + 1, 4)
                $val = Parse-Hex $hex
                Append-CodePoint $sb $val
                $i += 5
                continue
            }

            'U' {
                # \UXXXXXXXX — exactly 8 hex digits (Unicode scalar)
                if ($i + 8 -ge $len) {
                    throw "Invalid \U escape at index ${i}: expected 8 hex digits."
                }

                $hex = $Text.Substring($i + 1, 8)

                # Strictly enforce 8 hex digits for robustness
                if ($hex -notmatch '^[0-9A-Fa-f]{8}$') {
                    throw "Invalid \U escape at index ${i}: '$hex' is not 8 hex digits."
                }

                $cp = [Convert]::ToInt32($hex, 16)

                # Unicode scalar validation: 0..10FFFF, excluding surrogate range
                if ($cp -lt 0 -or $cp -gt 0x10FFFF) {
                    throw "Invalid Unicode code point U+$($hex.ToUpper()) at index ${i}."
                }
                if ($cp -ge 0xD800 -and $cp -le 0xDFFF) {
                    # Surrogates are not valid Unicode scalars; treat as literal escape to avoid corrupting text
                    [void]$sb.Append('\U')
                    [void]$sb.Append($hex)
                    $i += 9
                    continue
                }

                Append-CodePoint $sb $cp
                $i += 9
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

                # Unknown escape => treat as literal next char
                [void]$sb.Append($esc)
                $i++
                continue
            }
        }
    }

    $sb.ToString()
}
