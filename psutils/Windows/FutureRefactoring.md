
# Short-term Refactoring Plan

**Remark**:
This refactoring **task has been completed**.

## Thoughts about Current Design

I was thinking about how substitution of placeholders works in the current ExpandTemplate.ps1. A single Regex::Replace performs all placeholder substitutions at once, which seems like an  elegant solution, but has its disadvantages.

Practically all flow of control happens within a callback of this function. This makes errors more difficult to trace (e.g. you lose actual positions of the origin in error reports - positions are simply set to the function call), this may also lead to less readability and flexibility, especially when expanding functionality and placeholder syntax (e.g., when implementing expressions and code execution in the future).

I think it may be beneficial to replace a single Regex::Replace with iterative search for placeholders + individual substitution blocks in a straight loop, without callbacks. Pure regular expressions solution may become chaotic if we significantly enrich the syntax (e.g. more markup options rather than just {{ ... }}, nested markup, etc.), and combination with other approaches may be beneficial (e.g. adding state in terms of context structure, custom verifications beyond pure regular expressions, etc.).

## Quick Plan Short-term Refactoring of the Main Loop (Currently Regex::Replace with a Callback)

The single `Regex::Replace(..., MatchEvaluator)` is elegant for the “basic placeholder” case, but once we want richer syntax (optional heads, unquoted args, escapes, nested placeholders, future `{{= expr }}` blocks, etc.), a purpose-built scanner + loop buys us:

* clearer control flow (no deep callback stack)
* precise source locations (line/column) for errors
* easier support for escapes and nesting
* simpler, stepwise evolvability (you can slide in new node types without regex gymnastics)

Below is a practical way to evolve without a large-scale rewrite

### A pragmatic path forward

#### 1) Keep what works: reuse the inner parser

We already have a good `Parse-Placeholder` that tokenizes the inside of `{{ ... }}` into `{ Head, Pipeline[] }`. We **keep using** that. The only thing we’re **swapping** is **the outer “find/replace all placeholders”** stage.

#### 2) Replace the one-shot Regex with a streaming scanner

**Scan the template once**, from left to right, and copy text into a StringBuilder. When we **encounter** `{{`, capture everything up to the matching `}}` (honoring escapes like `\{{` and `\}}` that should not start / end **a placeholder**). Then:

* Normalize the inner text (trim per your rules)
* Parse-Placeholder
* Resolve head → initial value (var/env)
* Apply-Filters
* Append the expansion result to the output

This loop will give us deterministic behavior and good diagnostics.

#### Sketch (drop-in friendly)

~~~ csharp
function Expand-PlaceholdersStreaming {
  param(
    [Parameter(Mandatory)][string]$Text,
    [Parameter(Mandatory)][hashtable]$Variables,
    [switch]$Trace
  )

  $sb   = [System.Text.StringBuilder]::new()
  $pos  = 0
  $len  = $Text.Length

  # Small helpers
  function Peek([int]$i) {
    if ($i -ge 0 -and $i -lt $len) { $Text[$i] } else { $null }
  }
  function IsEscapedOpen([int]$i) {
    # \{{ should be treated as literal
    ($i -gt 0) -and ($Text[$i-1] -eq '\')
  }
  function IsEscapedClose([int]$i) {
    # \}} should be treated as literal
    ($i -gt 0) -and ($Text[$i-1] -eq '\')
  }

  while ($pos -lt $len) {
    $i = $Text.IndexOf('{{', $pos)
    if ($i -lt 0) {
      [void]$sb.Append($Text.Substring($pos))
      break
    }

    # copy literal up to '{{'
    [void]$sb.Append($Text.Substring($pos, $i - $pos))

    # escaped open? emit literally and continue
    if (IsEscapedOpen $i) {
      # keep one '{' (the second one) because the backslash escapes the first
      # or simply drop the backslash and output '{{'
      [void]$sb.Append('{{')
      $pos = $i + 2
      continue
    }

    # find matching '}}' taking care of escapes
    $j = $i + 2
    $found = $false
    while ($j -lt $len) {
      if ((Peek($j) -eq '}') -and (Peek($j+1) -eq '}')) {
        if (-not (IsEscapedClose $j)) { $found = $true; break }
        # it’s escaped, emit a '}' and keep scanning
        $j += 2
        continue
      }
      $j++
    }
    if (-not $found) {
      throw "Unclosed placeholder. Expected '}}' near index $i."
    }

    $inner = $Text.Substring($i + 2, $j - ($i + 2))

    if ($Trace) {
      Write-Host "Processing placeholder:`n  {{ $inner }}"
    }

    try {
      # parse → { Head, Pipeline }
      $ph = Parse-Placeholder -InnerText $inner

      # resolve head value
      $headVal = Resolve-Head `
        -Head $ph.Head `
        -Variables $Variables `
        -Trace:$Trace

      # apply filters
      $expanded = Apply-Filters `
        -Value $headVal `
        -Pipeline $ph.Pipeline `
        -Trace:$Trace

      [void]$sb.Append([string]$expanded)
    }
    catch {
      throw "Error in placeholder '{{ $inner }}': $($_.Exception.Message)"
    }

    $pos = $j + 2
  }

  $sb.ToString()
}

function Resolve-Head {
  param(
    [Parameter(Mandatory)][string]$Head,
    [Parameter(Mandatory)][hashtable]$Variables,
    [switch]$Trace
  )

  # Expected heads:
  #   var.Name
  #   env.NAME
  $parts = $Head.Split('.', 2)
  if ($parts.Count -lt 2) {
    throw "Invalid placeholder head '$Head'. Use 'var.Name' or 'env.NAME'."
  }
  $ns   = $parts[0].Trim()
  $name = $parts[1].Trim()

  switch ($ns.ToLowerInvariant()) {
    'var' {
      if (-not $Variables.ContainsKey($name)) {
        throw "Variable '$name' not defined."
      }
      $val = $Variables[$name]
      if ($Trace) { Write-Host "  Head var.$name = $val" }
      return $val
    }
    'env' {
      $val = [System.Environment]::GetEnvironmentVariable($name)
      if ($null -eq $val) {
        throw "Environment variable '$name' not defined."
      }
      if ($Trace) { Write-Host "  Head env.$name = $val" }
      return $val
    }
    default {
      throw "Invalid namespace '$ns' in head '$Head'."
    }
  }
}
~~~

In minimal **integration**, **replace** the current one-shot `Regex::Replace` **with** `Expand-PlaceholdersStreaming -Text $raw -Variables $VARS -Trace:$Trace`.

#### 3) Advantages of scanning vs. Regex::Replace

* **Escapes & literal braces**: We already support `\{{` / `\}}`. Regex can do it, but explicit scanning makes the rule obvious and future‐proof.
* **Better errors**: We can produce reports like `“Unclosed placeholder at line 48, col 13”` by tracking line/col while scanning.
* **Nesting**: If we want `{{ var.A | prepend:"{{ var.B }}" }}`, we can detect inner `{{...}}` segments while scanning. We don't recommending nested execution yet, but we can also go into this direction if it turns necessary.
* **Streaming large files**: Regex loads full text and builds matches. A scanner copies chunks into a StringBuilder and evaluates as we go.

#### 4) Performance

For typical config/template sizes, the scanner is fast enough. It’s O(N), same as the regex approach in practice, and we avoid repeated callbacks into PowerShell with the general overhead of `MatchEvaluator`. If it ever mattered, we could keep the scan in .NET/C# and call or existing PowerShell functions (no need for now).

#### 5) Migration plan (low-risk)

1. Add Resolve-Head (the code above) and the streaming function.
1. Toggle behind a switch param -Engine Streaming (default to the current behavior initially). This is optional, we can try to fully switch to the suggested approach.
1. Run the existing template test set (especially the `TemplateShort.txt.tmpl`) and compare outputs.
1. Once identical, flip the default to streaming (optional - when choosing gradual switch).


