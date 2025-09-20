
# Future Extensions of the Template Engine

## Initial Proposal

### Notes - Possible Scripting Extensions of the ExpandTemplate.ps1 (the Template Engine)

This idea is about allowing ***computed values*** inside templates. Recommended are two tiers of “power,” each with its own markup so users immediately understand the risk level:

#### Tier 1 — Safe inline expressions (no commands)

**Markup:** `{{ expr: <expression> | filters... }}`

* Intended for simple math, string ops, property/method calls, and variable references—**no pipelines or commands**.
* Example:

  * `{{ expr: (2+2) }}` → `4`
  * `{{ expr: 'Code.exe'.ToUpper() }}` → `CODE.EXE`
  * `{{ expr: var.Title + ' (Portable)' | regq }}` → escapes quotes for `.reg`

**Rationale**: This cowers majority of “computed text” needs without letting arbitrary PowerShell code run. Implementation can validate the expression (e.g., reject `| ; & > <` and command keywords), then evaluate via a tiny evaluator or a restricted `ScriptBlock` (see notes below).

#### Tier 2 — Full PowerShell (opt-in)

**Inline:** `{{ ps: <PowerShell expression> | filters... }}`
**Block:**

~~~powershell
{% ps %}
# Any PowerShell statements
$y = Get-Date
"$($y.ToString('yyyy-MM-dd'))"
{% endps %}
~~~

* Inline: evaluate an expression and capture its string output.
* Block: run a script block; capture pipeline output (joined by newlines) as the replacement.
* **Guarded by a switch** like `-EnableExpressions` or `-EnablePowerShellCode` so it’s off by default.
* You can pass your current variables and environment in as `$vars` and `$env:` for convenience:

  * `{{ ps: $vars['Title'] + ' — ' + $env:USERNAME }}`

**Why this is necessary?** When you really need the system functionality (lookups, file reads, conditional logic), this is a flexible solution.

#### How it fits the current engine

* **Delimiters stay the same**: `{{ ... }}` for inline, and add `{% ps %}...{% endps %}` for multi-line PowerShell.
* **Filters still apply after evaluation** (like in the current placeholder syntax):
  Example: `{{ ps: (Get-Date).ToString('yyyy-MM-dd') | append:" 00:00" }}`
  Example: `{{ expr: (4*0.0283495) | append:" kg" }}`

#### Practical Examples

##### 1. Inline, safe expression

~~~reg
"Icon"="{{ expr: env.USERPROFILE + '\AppData\Local\Programs\Microsoft VS Code\Code.exe' | regq }}"
~~~

##### 2. Inline, full PowerShell (opt-in)

~~~reg
@="\"{{ ps: Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe' | regq }}\" \"%1\""
~~~

##### 3. Block PowerShell

~~~
; Build a complex string in PS, then emit it
{% ps %}
$exe = Join-Path $env:LOCALAPPDATA 'Programs\Microsoft VS Code\Code.exe'
'"' + $exe + '" "%1"'
{% endps %}
~~~

##### 4. Combining with filters

~~~text
{{ ps: [math]::Pow(2,10) | append:" bytes" }}
{{ expr: ('C:\Users\' + env.USERNAME + '\Desktop') | regq }}
~~~

#### Safety & UX recommendations

* **Disabled by default.** Require `-EnableExpressions` to allow any `ps:` or `{% ps %}` usage. Repoer error if found when disabled.
* **Timeouts.** Add `-ExpressionTimeoutSeconds 5` (or similar) so long-running code can’t hang expansion.
* **Scope.** Evaluate in an **isolated runspace** with no profile, and pass in:

  * `$vars` (your merged hashtable), `$env` (standard env), maybe a small **whitelist** of helper functions.
* **Sanitize `expr:`.** For Tier 1, reject tokens that enable commands/pipelines:

  * Disallow `| ; & > < \`n`etc., and cmdlets/keywords like `Get-`, `Invoke-`, `New-`, `Set-`, `ForEach-Object`, `Start-Process`, `;`, `|\`.
  * Allow only literals, `()`, `[]`, `.ToString()`, static .NET calls (`[math]::Round(...)`), operators.
* **Error messages.** Keep them precise: show the offending placeholder snippet and why it was rejected (e.g., “`expr:` does not allow pipelines; found `|`”).
* **Block output capture.** For `{% ps %}`: join the pipeline output with `"`n"\` (Windows newlines are fine in .reg comments and many value types).

---

#### Minimal implementation sketch (high level)

1. **Parser changes**

   * Inline head detection:

     * `var.<name>` / `env.<NAME>` (existing)
     * `expr:` → everything after `expr:` up to first `|` (or `}}`) is the expression text
     * `ps:`   → same as above but treated as “unsafe” (needs flag)
   * Block:

     * Scan for `{% ps %}` … `{% endps %}` and replace as a pre-pass before your `{{ ... }}` regex. The content between tags becomes the “expression” for evaluation.

2. **Evaluation**

   * `expr:`: validate string, then `ScriptBlock::Create(expr).Invoke()` in a controlled runspace, or build a tiny evaluator for math/string if you want to be extra-safe.
   * `ps:` and `{% ps %}`: `ScriptBlock::Create(code).Invoke()` in a **temporary runspace** created with:

     * No profile
     * Preloaded variables: `$vars = <hashtable>`, `$env:` available, maybe `$outBuilder` if you want to capture differently
     * Timeout via `Start-Job` + `Wait-Job -Timeout` or `PowerShell` API with CancellationToken

3. **Stringification**

   * Convert result to string with `Out-String` and trim trailing newline, or `.ToString()` if scalar.

4. **Filters**

   * Reuse the existing filter pipeline after evaluation.

---

#### Why the split

* **Clarity:** `expr:` looks safe; `ps:` looks powerful (and potentially risky). Users can pick consciously.
* **Extensibility:** Possible to add more DSL-like helpers later (e.g., `{{ json: var.Obj | indent:2 }}`) without enabling PS code execution.
* **Compatibility:** The current templates keep working as-is; this is a pure extension.

---
---
---

## Remarks after Review



Love the direction—your draft nails the big idea and cleanly separates “safe math/string-y expressions” from “full PowerShell,” which is exactly the right mental model for users. I read your proposal end-to-end and here’s focused feedback you can apply immediately.

### What’s strong already

* Two clear tiers with distinct syntax: `{{ expr: ... }}` for **safe** inline math/string ops, and `{{ ps: ... }}` / `{% ps %}...{% endps %}` for **opt-in** PowerShell. That maps perfectly to user intent and risk tolerance.&#x20;
* Filters still apply **after** evaluation—great for consistency; users don’t have to learn a new pipeline.&#x20;
* Off by default with an enable switch, plus timeouts and isolation: you’re thinking like a product owner *and* a security reviewer.&#x20;

### Gaps & risks to tighten

1. ## “Safe” expressions still need hard boundaries

   Even without pipes/commands, **method calls and static calls** can do damage:

   * `{{ expr: [IO.File]::Delete('C:\…') }}`
   * `{{ expr: (GetType).Assembly… }}` (reflection pivots)

   **Action:** Validate the parsed AST and only allow a very small set of node types and symbols. Do **not** rely on string find/replace of tokens; users can evade that. (See “Safe AST allow-list” below.)

2. ## Runspace “safety” isn’t automatic

   Programmatically setting **ConstrainedLanguage** isn’t universally supported and can be bypassed. Treat runspace isolation as **defense-in-depth**, not the one true guard. Your primary control for `expr:` should be AST validation; your control for `ps:` should be *isolation + an explicit allow policy*.&#x20;

3. ## Parser interactions

   `{% ps %}` blocks must be **removed/replaced** before your `{{ … }}` scanner runs, otherwise inner `{{` may look like placeholders. Your doc says this; just emphasize it as a pre-pass with robust delimiter scanning (support escaped `{%`/`%}` like `\{%`).&#x20;

4. ## Output semantics

   Decide (and document) for `ps:`/`{% ps %}`:

   * Join pipeline output with `"\r\n"`, then **trim a single trailing newline**.
   * Non-string results → `Out-String -Width 32767` then trim end.
     This keeps `.reg` and text outputs predictable.&#x20;

5. ## Error UX

   When scripting is disabled, error early with **clear tier context**:

   > `Expressions are disabled. Found 'ps:' at line X, col Y. Enable with -EnableExpressions or -ExpressionMode Full.`&#x20;

---

### Concrete recommendations

#### 1) CLI surface (simple but future-proof)

* `-ExpressionMode Disabled|Safe|Full` (default **Disabled**)

  * `Safe` → enables `expr:` **only**
  * `Full` → enables `expr:`, `ps:` and `{% ps %}` blocks
* `-ExpressionTimeoutSeconds 5` (applies to `ps:`/blocks; `expr:` executes synchronously and must be fast)
* `-ExpressionMaxOutputKB 256` (truncate with “… (truncated)” to avoid RAM bombs)
* `-ExpressionWorkingDir <path>` (optional; default to template’s folder)

This avoids proliferating switches (`-EnableExpressions`, `-EnablePowerShellCode`…), keeps it one knob.

#### 2) Safe AST allow-list for `expr:`

Use the parser, not regex. Rough shape:

```powershell
using namespace System.Management.Automation.Language

function Test-IsSafeExprAst {
  param([Ast]$Ast)

  switch ($Ast) {
    { $_ -is [ScriptBlockAst] }      { return ($_.BeginBlock -and (Test-IsSafeExprAst $_.BeginBlock)) }
    { $_ -is [PipelineAst] }         { return ($_.PipelineElements.Count -eq 1 -and (Test-IsSafeExprAst $_.PipelineElements[0])) }
    { $_ -is [CommandExpressionAst] }{ return (Test-IsSafeExprAst $_.Expression) }
    { $_ -is [ParenExpressionAst] }  { return (Test-IsSafeExprAst $_.Pipeline) }
    { $_ -is [BinaryExpressionAst] } { return (Test-IsSafeExprAst $_.Left) -and (Test-IsSafeExprAst $_.Right) -and
                                               ($_.Operator -in @('Add','Subtract','Multiply','Divide','Modulus','Format','Concat','Ieq','Ine','Ilt','Igt','Ile','Ige')) }
    { $_ -is [UnaryExpressionAst] }  { return ($_.TokenKind -in @('Minus','Plus','Not')) -and (Test-IsSafeExprAst $_.Child) }
    { $_ -is [ConstantExpressionAst] } { return $true }   # numbers, strings
    { $_ -is [VariableExpressionAst] } { return ($_.VariablePath.UserPath -in @('vars','env')) } # only $vars / $env
    { $_ -is [IndexExpressionAst] }  { return (Test-IsSafeExprAst $_.Target) -and (Test-IsSafeExprAst $_.Index) }
    { $_ -is [MemberExpressionAst] } {
        # Allow property access ONLY on $vars[...] results and strings. No method invocation.
        if ($_.Static) { return $false }
        if (-not $_.Member -is [StringConstantExpressionAst]) { return $false }
        # forbid InvokeMemberExpressionAst (method calls)
        return (Test-IsSafeExprAst $_.Expression)
    }
    { $_ -is [TypeExpressionAst] }   { return $false }  # disallow [Type]
    { $_ -is [HashtableAst] }        { return $false }  # keep it minimal initially
    { $_ -is [ArrayLiteralAst] }     { return @($_.Elements | ForEach-Object { Test-IsSafeExprAst $_ }) -notcontains $false }
    default { return $false }
  }
}
```

Evaluate like:

```powershell
$tokens = $null; $errors = $null
$ast = [Parser]::ParseInput($exprText, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw "Invalid expression: $($errors[0].Message)" }
if (-not (Test-IsSafeExprAst $ast)) { throw "expr: contains disallowed constructs." }

### Build a tiny sandbox state
$iss  = [Runspaces.InitialSessionState]::CreateDefault()
$iss.Commands.Clear(); $iss.Variables.Clear(); $iss.LanguageMode = 'NoLanguage'  # we invoke scriptblock compiled from AST anyway
$rs   = [Runspaces.RunspaceFactory]::CreateRunspace($iss)
$rs.Open()
$ps   = [PowerShell]::Create().AddScript($exprText).AddCommand('Out-String')
$ps.Runspace = $rs
$ps.AddArgument() | Out-Null
$result = ($ps.Invoke() -join "") -replace '\r?\n$',''
```

> Tip: for `expr:` you can keep it even simpler—**interpret** the AST yourself (arithmetic, string concat, var/env lookup). That’s the safest of all, just a bit more code.

#### 3) Execution model for `ps:` and `{% ps %}`

* **Isolation:** create a fresh runspace with `InitialSessionState`:

  * No profile, no modules auto-loaded
  * `LanguageMode = 'ConstrainedLanguage'` *if* supported; else leave Full but…
  * **No imported cmdlets** unless you deliberately add a tiny allow-list (`Get-Date`, `Join-Path`, etc.). Many scripts don’t need cmdlets at all; they just call .NET.
* **Inputs:** inject only:

  * `$vars` → your merged dictionary (read-only hashtable)
  * `$env`  → built-in provider is fine (read-only from your perspective)
  * Optionally a helper `$Out` function that safely appends to a StringBuilder if you want deterministic output capture.
* **Timeouts:** run the pipeline with `BeginInvoke()` and a `WaitHandle` (or `RunspaceInvoke` with a `CancellationToken` in PS 7+). On timeout, stop and throw a template error including line/column and a trimmed code preview.
* **Output capture:** `Out-String -Width 32767` at the end, `.TrimEnd("`r","`n")`.

#### 4) Parser integration (no surprises)

* **Inline:** in `Parse-Placeholder`, detect `expr:` and `ps:` heads. For `expr:`, take everything until the first unescaped `|` as the expression; for `ps:`, same. The remainder is your existing filter pipeline.
* **Block:** do a pre-pass over the template *before* placeholder scanning:

  * Scan for `{% ps %}` → find unescaped `{% endps %}` (no nesting initially).
  * Replace the entire block with a unique placeholder token (e.g., GUID), store its code text in a side map.
  * During expansion, when the token placeholder is hit, evaluate from the side map, **then** apply filters.
* **Escapes:** continue to honor `\{{`, `\}}`, and add `\{%`, `\%}` for literal percent-blocks.

#### 5) Error & trace UX

* Use your unified trace lines:

  * ` [exp] {{ expr: ... }}` / ` [exp] {{ ps: ... }}` with **elapsed ms**.
  * On failure: ` [err] {{ expr: … }}: <message>`.
* For blocks: ` [exp] {% ps %} (#lines=N, ms=X.Y)`; on timeout: ` [err] {% ps %} timeout after N s`.

---

### Pester test checklist to add

**Disabled by default**

* Using `{{ expr: 1+1 }}` → error “Expressions disabled”.
* Using `{{ ps: 1+1 }}` / `{% ps %}` → error “Expressions disabled”.

**expr: happy path (Safe)**

* Arithmetic: `{{ expr: 2+2 }}` → `4`
* String concat: `{{ expr: 'a' + 'b' }}` → `ab`
* Vars/env: `{{ expr: vars['Name'] + ' ' + env.USERNAME }}`

**expr: blocked constructs**

* Static type: `{{ expr: [IO.File]::Delete('x') }}` → blocked
* Method call: `{{ expr: 'x'.ToUpper() }}` → blocked (unless you explicitly allow)
* Pipeline/semicolon: `{{ expr: 1 | Out-Null }}` → blocked

**ps: happy path (Full)**

* Inline: `{{ ps: (Get-Date).Year }}` → digits
* Block: date formatting, Join-Path, multi-line output, filters after block.

**timeouts**

* `{% ps %} Start-Sleep 10 {% endps %}` with 1s timeout → fails fast.

**filters after eval**

* `{{ expr: 1024 | append:" bytes" }}` → “1024 bytes”
* `{{ ps: 'a b' | urlencode }}` → “a%20b”

**escape interactions**

* `\{% ps %}` and `\%}` render literally
* `\{{ expr: 1+1 \}}` doesn’t evaluate

---

### Tiny tweaks to your doc

* Rename the on/off switch to a **single** `-ExpressionMode` as above; it simplifies the story.&#x20;
* In **Tier 1** examples, avoid showing `.ToUpper()` unless you plan to allow method calls; show `'text'.ToString()` only if you allow that explicitly.&#x20;
* In **Safety** section, explicitly state you’ll **reject Type expressions** (`[Type]`), **member invocations**, and any **pipeline constructs** in `expr:`.&#x20;
* Clarify block join semantics (“pipeline output is joined by CRLF; final newline trimmed”) and that filters apply to the captured text.&#x20;

---

If you want, I can draft the *actual* `Evaluate-SafeExpression` (AST walker) and a minimal `Evaluate-PsBlock` (runspace with timeout) that drop straight into your current script without touching the rest of the engine.






