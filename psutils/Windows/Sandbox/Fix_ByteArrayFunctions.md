
# Fixing the Issue with Filter Functions Returning Byte[]

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

Test code (**quick sanity check**):

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

When calling functions that return a byte array (.NET type byte[]), the actual result is of type object[]. Therefore, attempted conversion back to a string fails (more details below).

## The Fix

The root cause is **PowerShell’s automatic enumeration**.

* In PowerShell, when a function outputs an **array**, the engine *enumerates* it into the pipeline (strings are the exception).
* So when your decoder returns a `byte[]`, that array is **expanded into individual bytes** on the pipeline, and the caller ends up with an **`object[]` of `byte`** elements.
* That’s why your `$c.GetType().FullName` is `System.Object[]`, even though you returned a `byte[]` from .NET.

The `utf16` fix (new version of the function) “works” because the .NET binder can coerce an `object[]` of `byte` to a `byte[]` when calling `GetString(bytes)`. This is just auto-conversion, not the type that was intended to carry through.

## The fix: return byte[] *without enumeration*

Use **`Write-Output -NoEnumerate`** inside any filter that returns raw bytes. That *prevents the array from being expanded on the pipeline*, so *the caller receives* a genuine `byte[]`.

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

Below is the test code to check the effect. The only difference is that the new `Filter-FromBase64` is called instead of `Filter-FromBase64Old`. The old version of `utf16Old` is still used and this does not prevent getting the correct result of conversion of byte array to a string.

~~~powershell
$a = "Initial String"
Write-Host "a = `"$a`""
$b = Filter-Base64 $a
Write-Host "b = `"$b`""
$c = Filter-FromBase64 $b  # Call the newer variant
Write-Host "c = `"$c`""
$d = utf16Old $c     # Older variant in this conversion should also work
Write-Host "d = `"$d`""  # correct: "Initial String" ✅

# Verify types after conversion:
Write-Host "  Type of a: $($a.GetType().FullName)"  # System.String"
Write-Host "  Type of b: $($b.GetType().FullName)"  # System.String
Write-Host "  Type of c: $($c.GetType().FullName)"  # System.Byte[] ✅
~~~

## Why the New `utf16` also “Fixed” the Conversion

This line:

~~~powershell
$Value = [System.Text.Encoding]::Unicode.GetString($value)
~~~

works because the binder sees an `object[]` whose elements are bytes and **coerces** it to `byte[]` to match the .NET overload. It’s convenient, but it hides the real issue (enumeration). With `-NoEnumerate` in your byte-producing filters, you can switch back to the clean, explicit pattern:

~~~powershell
'utf16' {
    # expect byte[]
    $Value = [Text.Encoding]::Unicode.GetString([byte[]]$Value)
}
~~~

or keep the simpler without the cast - both will work once the upstream return is a real `byte[]`.

## Do we need As-Bytes / Is-ByteVector?

Once you ensure all **byte-producing filters** use `-NoEnumerate`, the type flow becomes predictable:

* `base64` / `hex` → **string**
* `frombase64` / `fromhex` → **byte[]** (unless `"utf16"`/etc. is requested)
* `gzip` → **byte[]**, `gunzip` → **string**
* `strfrombase64` / `strfromhex` → **string**

You can keep the robust helpers if you like, The robust helpers can be kept if wanted, but they are no longer necessary to fix things, they are just safety nets.

## Bottom line

* The weird `object[]` comes from **PowerShell enumerating arrays** emitted by functions.
* **Always** use `Write-Output -NoEnumerate $bytes` in filters that output byte arrays.
* The `frombase64:"utf16"` / `strfrombase64` paths will continue to work, and `frombase64 | utf16` will also work correctly once the decoder returns a real `byte[]`.








# Mechanisms behind Issues with Byte[] Return Values

Below is a deep-dive into what’s going on under the hood in PowerShell and why the `byte[]` turns into `object[]` when returned fom a function.

## How PowerShell’s Pipeline “Enumerates” Arrays

* In PowerShell, **anything a function writes is sent to the pipeline**. That includes `Write-Output`, `return`, or just writing a value as the last expression.
* **By default**, when a value reaches the pipeline, PowerShell checks if it’s a **collection** (roughly: implements .NET `IEnumerable`).

  * If it is, PowerShell **enumerates it** and emits each element **one by one**.
  * **Exception:** strings are special-cased and are **not** enumerated character-by-character, even though they implement `IEnumerable<char>`.

So when a function returns a `byte[]`, PowerShell treats it like “a sequence of bytes” and sends them **individually** down the pipeline. If the caller captures the output, they’ll get **`object[]`** (an array whose elements are bytes), *not* a single `byte[]`.

#### Quick Demo

~~~powershell
function Get-Bytes1 { ,([byte[]](65,66,67)) }         # returns *one* object: a byte[] wrapped in a 1-element array
function Get-Bytes2 { [byte[]](65,66,67) }             # enumerates -> 65, 66, 67
function Get-Bytes3 { Write-Output ( [byte[]](65,66,67) ) } # enumerates by default
function Get-Bytes4 { Write-Output -NoEnumerate ([byte[]](65,66,67)) } # <-- preferred

(Get-Bytes1).GetType().FullName  # System.Object[]  (1 element, which is a byte[])
(Get-Bytes2).GetType().FullName  # System.Object[]  (3 elements: 65,66,67)
(Get-Bytes3).GetType().FullName  # System.Object[]  (3 elements)
(Get-Bytes4).GetType().FullName  # System.Byte[]    ✅ exact array type preserved
~~~

**Takeaway:** If a function needs to output a `byte[]` as a single object, use **`Write-Output -NoEnumerate $bytes`**. That prevents automatic enumeration.

(Using the unary comma `,$bytes` also “protects” it from enumeration, but that creates a **one-element object\[]** *containing* a byte\[], which is often not what you want. `-NoEnumerate` keeps the exact type.)

## “Coercion” from `object[]` to `byte[]` (Why the `utf16` Seemed to Work)

When a .NET method is called from PowerShell, the **PowerShell binder** tries to match the target parameter types:

* If the method expects `byte[]` and you pass an **array** (`object[]`) whose elements can be converted to `byte`, PowerShell will **convert element-by-element** and pass a proper `byte[]`.
* That’s why this works:

  ~~~powershell
  $oa = 65,66,67            # object[] of Int32
  [Text.Encoding]::ASCII.GetString($oa)  # binder converts each to byte first
  ~~~

* If any element cannot be converted to `byte` (e.g., outside 0–255, or a non-numeric), binding will fail.

So the change:

~~~powershell
## Worked because the binder converted object[] of bytes -> byte[]
$Value = [Text.Encoding]::Unicode.GetString($value)
~~~

“worked by accident” - the binder helped, but you were still shipping an enumerated array. Better to **preserve the `byte[]` earlier** (with `-NoEnumerate`) so you keep full control.

## Is “Enumerating” Tied to .NET’s `IEnumerable`?

**Conceptually, yes.** PowerShell looks at values and, if they’re **collections** (most things implementing `IEnumerable` or arrays), it will enumerate them when outputting to the pipeline. A few extra notes:

* **Strings** are special-cased: not enumerated.
* **Hashtables / dictionaries** do enumerate (you’ll see key/value pairs) if you output them *as objects*; but formatting can hide that.
* **PSCustomObject** is a single object (not a collection) and won’t be enumerated.

## How to Keep Types Predictable in the Template Engine

Here are solid rules that can be relied upon:

1. **Any filter that outputs bytes must do**:

   ~~~powershell
   Write-Output -NoEnumerate $byteArray
   ~~~

   That guarantees downstream sees `System.Byte[]`.

2. **Decoders** should be **string-in / byte[]-out**:

   ~~~powershell
   function Filter-FromBase64 {
       param([string]$Value)
       [byte[]]$bytes = [Convert]::FromBase64String($Value)
       Write-Output -NoEnumerate $bytes
   }
   ~~~

3. **Encoded-string helpers** (like `strfrombase64` or `frombase64:"utf16"`) should **decode to bytes** and immediately **map to text** using the requested encoding, so they return **`string`**.

4. If you want a **safety guard** to catch accidental leftover binary:

   ~~~powershell
   function Is-ByteVector([object]$v) {
       if ($v -is [byte[]]) { return $true }
       if ($v -is [System.Array]) {
           $et = $v.GetType().GetElementType()
           if ($et) { return ($et -eq [byte]) }
           if ($v.Length -gt 0 -and $v[0] -is [byte]) { return $true } # object[] of byte
       }
       return $false
   }

   $out = Apply-Filters ...
   if (Is-ByteVector $out) {
       throw "Placeholder ended with binary data. Finish with frombase64:'utf16' / strfrombase64 (or hex equivalents)."
   }
   ~~~

## Condensed Summary

* **Return a `byte[]` without enumeration:**
  `Write-Output -NoEnumerate $bytes`
* **Prevent *any* enumeration (but wraps as object[]):**
  `,$bytes`  (one-element array containing the byte[])
* **Array subexpression (always creates a new array):**
  `@($x)`  (often used to ensure “array of outputs”; still enumerates contents)
* **Binder converts `object[]` → `byte[]` when a method parameter demands it**, element by element.

With these in place, you can keep your engine’s type flow clean (string ↔ byte[]), your round-trip filter combinations correct, and the `utf16` filter can be the “clear intent” option rather than a workaround.

