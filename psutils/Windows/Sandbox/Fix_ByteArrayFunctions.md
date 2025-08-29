
# Fix for Functions (Filters) Returning Byte[]

## Old Filter Functions

~~~powershell

# Conversion of byte array to string (old style)
function utf16Old { 
    param([Parameter(Mandatory)] $Value)
    $bytes = As-Bytes $Value
    $Value = [System.Text.Encoding]::Unicode.GetString($bytes)
    return $Value
}

# Conversion of byte array to string (new style, PowerShell coerces object[] with
# elements of actual type byte to convert to byte[] before calling GetString):
function utf16 { 
    param([Parameter(Mandatory)] $Value)
    $Value = [System.Text.Encoding]::Unicode.GetString($value)
    return $Value
}


# Conversion to string
function As-String {
    param([Parameter(Mandatory)] [object]$Value)
    if ($Value -is [byte[]]) { return [System.Text.Encoding]::Unicode.GetString($Value) }
    return [string]$Value
}

# Conversion to byte array
function As-Bytes {
    param([Parameter(Mandatory)] [object]$Value)
    if ($Value -is [byte[]]) { return $Value }
    $s = [string]$Value
    return [System.Text.Encoding]::Unicode.GetBytes($s)
}

# Performs base64 encodinng
function Filter-Base64   { param($v) return [System.Convert]::ToBase64String((As-Bytes $v)) }

# Performs base64 decoding
function Filter-FromBase64Old {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )
    try {
        # Always return a true [byte[]]
        return [System.Convert]::FromBase64String($Value)
    } catch {
        throw "frombase64: invalid Base64 input ($($_.Exception.Message))."
    }
}

# Conversion to lover-case hexadecimal string:
function Filter-Hex {
    param($v)
    $bytes = As-Bytes $v
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '')
}

# Conversion of hexadecimal string to byte array:
function Filter-FromHexOld {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )
    $hex = $Value -replace '\s+', ''
    if ($hex.Length % 2 -ne 0) {
        throw "fromhex: hex string length must be even."
    }
    $list = New-Object System.Collections.Generic.List[byte]
    for ($i = 0; $i -lt $hex.Length; $i += 2) {
        try {
            $b = [System.Convert]::ToByte($hex.Substring($i,2), 16)
        } catch {
            throw "fromhex: invalid hex at position $i."
        }
        [void]$list.Add($b)
    }
    return $list.ToArray()   # => [byte[]]
}

# Compression using GZip
function Filter-GzipOld {
    param($v)
    $in = As-Bytes $v
    $msOut = New-Object System.IO.MemoryStream
    $gzip = New-Object System.IO.Compression.GzipStream($msOut, [System.IO.Compression.CompressionLevel]::Optimal, $true)
    $gzip.Write($in, 0, $in.Length)
    $gzip.Dispose()
    return $msOut.ToArray()
}

# Unzipping using GZip
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
~~~

Test code:

~~~powershell
$a = "Initial String"
Write-Host "a = `"$a`""
$b = Filter-Base64 $a
Write-Host "b = `"$b`""
$c = Filter-FromBase64Old $b  # Call the older variant
Write-Host "c = `"$c`""
$d = utf16Old $c           # Older variant
Write-Host "d = `"$d`""    # Wrong result (array of objects converted to string)

# Verify types after conversion:
Write-Host "  Type of a: $($a.GetType().FullName)"  # System.String"
Write-Host "  Type of b: $($b.GetType().FullName)"  # System.String
Write-Host "  Type of c: $($c.GetType().FullName)"  # System.Object[] - problematic
~~~

**The Issue**:

When calling functions that return a byte array (.NET type byte[]), the actual result is of type object[]. Therefore, attempted conversion fails (more details below).

Test code with the new string-to-bytes filter:

## The Fix

You nailed the root cause: it’s **PowerShell’s automatic enumeration**.

* In PowerShell, when a function outputs an **array**, the engine *enumerates* it into the pipeline (strings are the exception).
* So when your decoder returns a `byte[]`, that array is **expanded into individual bytes** on the pipeline, and the caller ends up with an **`object[]` of `byte`** elements.
* That’s why your `$c.GetType().FullName` is `System.Object[]`, even though you returned a `byte[]` from .NET.

Your `utf16` fix “worked” because the .NET binder can coerce an `object[]` of `byte` to a `byte[]` when calling `GetString(bytes)`. It was just auto-conversion, not the type you intended to carry through.

## The fix: return byte\[] *without enumeration*

Use **`Write-Output -NoEnumerate`** inside any filter that returns raw bytes. That prevents the array from being expanded on the pipeline, so the caller receives a genuine `byte[]`.

### Minimal patches

~~~powershell
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
    Write-Output -NoEnumerate $bytes       # <— critical
}

# Do the same for ANY filter that outputs bytes (e.g., gzip):
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
    Write-Output -NoEnumerate $bytes       # <— critical
}
~~~

> You don’t need `return` — `Write-Output -NoEnumerate` is the reliable way in PowerShell to output an array as a **single object**.

### Quick sanity check (now passes)

~~~powershell
$a = "Initial String"
Write-Host "a = `"$a`""
$b = Filter-Base64 $a
Write-Host "b = `"$b`""
$c = Filter-FromBase64 $b  # Call the newer variant
Write-Host "c = `"$c`""
$d = utf16Old $c     # Older variant in this conversion should also work
Write-Host "d = `"$d`""  # correct: "Initial String"

# Verify types after conversion:
Write-Host "  Type of a: $($a.GetType().FullName)"  # System.String"
Write-Host "  Type of b: $($b.GetType().FullName)"  # System.String
Write-Host "  Type of c: $($c.GetType().FullName)"  # System.Byte[]
~~~

## Why your `utf16` change “fixed” the path

This line:

~~~powershell
$Value = [System.Text.Encoding]::Unicode.GetString($value)
~~~

works because the binder sees an `object[]` whose elements are bytes and **coerces** it to `byte[]` to match the .NET overload. It’s convenient, but it hides the real issue (enumeration). With `-NoEnumerate` in your byte-producing filters, you can switch back to the clean, explicit pattern:

~~~powershell
'utf16' {
    # expect byte[]
    $Value = [Text.Encoding]::Unicode.GetString( [byte[]]$Value )
}
~~~

(or keep your simpler line—both will work once the upstream return is a real `byte[]`).

## Do we need As-Bytes / Is-ByteVector?

Once you ensure all **byte-producing filters** use `-NoEnumerate`, your type flow becomes predictable:

* `base64` / `hex` → **string**
* `frombase64` / `fromhex` → **byte\[]** (unless `"utf16"`/etc. is requested)
* `gzip` → **byte\[]**, `gunzip` → **string**
* `strfrombase64` / `strfromhex` → **string**

You can keep the robust helpers if you like, but they’re no longer band-aids — they’re just safety nets.

## Bottom line

* The weird `object[]` comes from **PowerShell enumerating arrays** emitted by functions.
* **Always** use `Write-Output -NoEnumerate $bytes` in filters that output byte arrays.
* Your `frombase64:"utf16"` / `strfrombase64` paths will continue to work, and `frombase64 | utf16` will also work correctly once the decoder returns a real `byte[]`.
