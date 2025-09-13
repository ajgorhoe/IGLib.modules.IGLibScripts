
# PowerShell Template Engine - Filter Arguments


This describes in more detail how filter arguments are parsed.

# Filter argument rules

## 1) General placeholder grammar

~~~
{{ head | filter[:arg[:arg...]] | filter2[:arg...] | ... }}
~~~

* **head**: `var.Name` or `env.NAME`
* Filters are **piped** with `|`.
* Filter **arguments** are separated with `:` (colon).
* Whitespace around tokens is ignored.

## 2) Two kinds of arguments

You can pass each argument either:

* **Unquoted**: a single token with no spaces or special delimiters
  Allowed chars: anything except whitespace, `:`, `|`, `}`
  Examples: `North`, `abc123`, `C:\Temp`, `\\server\share`
* **Double-quoted**: allows spaces and delimiters, with limited escapes
  Examples: `"North East"`, `"dir1\dir2\icon.png"`, `"a:b|c}"`

## 3) Escaping inside **double-quoted** args

We purposefully keep this minimal and predictable:

* `\"` → `"` (quote in the argument)
* `\\` → `\` (single backslash)
* **Any other** backslash sequence is **preserved literally**:

  * `\d` ⇒ `\d`
  * `\n` ⇒ `\n` (not a newline)
  * `\x21` ⇒ `\x21`
* A **trailing backslash** before the closing quote is preserved as `\`.
* Newlines are allowed *inside* quoted arguments and are preserved as written.

This means: only `\"` and `\\` are “active”; everything else stays exactly as typed.

## 4) Unquoted args have **no escaping**

* Backslashes, digits, etc., are taken literally: `\x21` stays `\x21`.
* If you need spaces, `:`, `|`, or `}`, use quotes.

## 5) Trimming & case

* Whitespace around `|`, `:`, and tokens is ignored.
* Filter names are **case-insensitive**.
* Argument text is passed through **as parsed** (no extra trimming inside quotes).

## 6) Empty arguments

* Use `""` to pass an empty string.
* (Unquoted empty isn’t possible; there must be at least one character.)

## 7) Examples

**Unquoted OK**

~~~
replace:old:new
pathappend:dir1/dir2/icon.png
~~~

**Use quotes when needed**

~~~
replace:"used to demonstrate":"demonstrating"
prepend:"The path is: "
pathappend:"dir1\dir2\icon.png"
replace:"\\":"/"
~~~

**Backslash behavior in quoted args**

~~~
"abc\\def"   -> abc\def
"one\"two"   -> one"two
"\x41"       -> \x41   (literal backslash + x + 41)
"dir1\dir2"  -> dir1\dir2
~~~

**Mixed**

~~~
{{ var.PathWin | pathappend:"dir1\dir2\icon.png" | replace:"\\":"/" | prepend:"The path is: " }}
~~~
Eventually, semantics could be changed (e.g., make `\n` become a newline inside quoted args). One could add an **optional** “interpreted string” mode or a separate filter to translate C/Java/C# escapes after parsing. For now, the rules above keep argument parsing simple, lossless, and predictable.

