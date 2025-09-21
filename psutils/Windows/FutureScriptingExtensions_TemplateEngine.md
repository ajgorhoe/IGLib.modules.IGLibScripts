
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

### What’s strong already

* Two clear tiers with distinct syntax: `{{ expr: ... }}` for **safe** inline math/string ops, and `{{ ps: ... }}` / `{% ps %}...{% endps %}` for **opt-in** PowerShell. That maps perfectly to user intent and risk tolerance.
* Filters still apply **after** evaluation—great for consistency; users don’t have to learn a new pipeline.
* Off by default with an enable switch, plus timeouts and isolation: you’re thinking like a product owner *and* a security reviewer.

### Gaps & risks to tighten

1. ## “Safe” expressions still need hard boundaries

   Even without pipes/commands, **method calls and static calls** can do damage:

   * `{{ expr: [IO.File]::Delete('C:\…') }}`
   * `{{ expr: (GetType).Assembly… }}` (reflection pivots)

   **Action:** Validate the parsed AST and only allow a very small set of node types and symbols. Do **not** rely on string find/replace of tokens; users can evade that. (See “Safe AST allow-list” below.)

2. ## Runspace “safety” isn’t automatic

   Programmatically setting **ConstrainedLanguage** isn’t universally supported and can be bypassed. Treat runspace isolation as **defense-in-depth**, not the one true guard. Your primary control for `expr:` should be AST validation; your control for `ps:` should be *isolation + an explicit allow policy*.

3. ## Parser interactions

   `{% ps %}` blocks must be **removed/replaced** before your `{{ … }}` scanner runs, otherwise inner `{{` may look like placeholders. Your doc says this; just emphasize it as a pre-pass with robust delimiter scanning (support escaped `{%`/`%}` like `\{%`).

4. ## Output semantics

   Decide (and document) for `ps:`/`{% ps %}`:

   * Join pipeline output with `"\r\n"`, then **trim a single trailing newline**.
   * Non-string results → `Out-String -Width 32767` then trim end.
     This keeps `.reg` and text outputs predictable.

5. ## Error UX

   When scripting is disabled, error early with **clear tier context**:

   > `Expressions are disabled. Found 'ps:' at line X, col Y. Enable with -EnableExpressions or -ExpressionMode Full.`

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

~~~powershell
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
~~~

Evaluate like:

~~~powershell
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
~~~

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

* Rename the on/off switch to a **single** `-ExpressionMode` as above; it simplifies the story.
* In **Tier 1** examples, avoid showing `.ToUpper()` unless you plan to allow method calls; show `'text'.ToString()` only if you allow that explicitly.
* In **Safety** section, explicitly state you’ll **reject Type expressions** (`[Type]`), **member invocations**, and any **pipeline constructs** in `expr:`.
* Clarify block join semantics (“pipeline output is joined by CRLF; final newline trimmed”) and that filters apply to the captured text.


---
---
---

## New Improved Plan



Just three heads keeps the surface simple and still gives clear safety boundaries:

* `{{ expr: ... }}` → **safe** expression, returns a value (filters apply), requires **Safe** (or Full) mode.
* `{{ exprps: ... }}` → **full PowerShell expression**, returns a value (filters apply), requires **Full** mode.
* `{{ ps: ... }}` → **full PowerShell code block**, **returns nothing** (empty string in output), allows side-effects in a shared context, requires **Full** mode.

Below are concrete suggestions to make this model predictable, safe, and easy to implement in your current engine.

---

### Behavioral contract (what users can rely on)

#### 1) Execution order & shared context

* Process placeholders **left → right** with your streaming scanner (which you already have).
* Maintain a **single shared runspace** *only when* `ExpressionMode=Full`. Every `{{ ps: ... }}` and `{{ exprps: ... }}` runs in that runspace; variables set in one placeholder are visible to later placeholders.
* In **Safe** mode: no runspace is created; only `expr:` is allowed and it can reference **\$vars** and **\$env** (not `$a`, etc.).

#### 2) Output shaping

* `expr:`/`exprps:`: evaluate → stringify → apply filters.

  * Strings: use as-is.
  * Numbers/DateTime: convert with **invariant culture**; then filters.
* `ps:`: execute; capture pipeline output but **discard it** (return empty string).

  * If the user writes a `ps:` with filters (`{{ ps: ... | trim }}`), **throw an error** like:
    “`ps:` code blocks don’t produce output; filters are not allowed.”
* Newline hygiene: when you do stringify, **trim a single trailing newline** so `Out-String` results don’t bleed a blank line.

#### 3) Modes & gating

* Single knob: `-ExpressionMode Disabled|Safe|Full` (default **Disabled**).

  * **Disabled:** all three heads error with a clear message.
  * **Safe:** only `expr:` allowed; `exprps:`/`ps:` error with “requires Full mode.”
  * **Full:** all three allowed.
* Hard limits (configurable):

  * `-ExpressionTimeoutSeconds` (applies to `exprps:` and `ps:`)
  * `-ExpressionMaxOutputKB` (truncate with “… (truncated)”)
  * Optional `-ExpressionWorkingDir` (defaults to template folder)

---

### Safety model

#### `expr:` (safe expressions)

* **No runspace needed** (fast). Parse the text and validate with an **AST allow-list**. Only allow:

  * Literals (numbers/strings), `()`, unary/binary ops (`+ - * / %`, comparisons).
  * Array/`[]` indexing and property access **on simple values**.
  * **Variables limited to** `$vars` and `$env` (in Safe mode).
    In **Full mode**, you may *optionally* also allow plain identifiers (`$a`) so safe expressions can read runspace variables set by `ps:`—still no methods/pipelines/types.
* **Disallow**: pipelines, method calls (`.ToUpper()`), type literals (`[IO.File]::…`), scriptblocks, `;`, `&`, redirection, reflection. If any appear, error: “`expr:` contains disallowed construct ‘…’”.

> Implementation tip: keep the allow-list tight now; you can always loosen it later.

#### `exprps:` (full expression)

* Runs in the **shared runspace** (Full mode only).
* Treat it as a single **expression** scriptblock (not statements). If users want statements/control flow, they should use `ps:`.
* Apply timeout and output limits like `ps:`. Convert the result to string as for `expr:`.

#### `ps:` (code block with side-effects)

* Runs in the shared runspace (Full mode only).
* Accepts **statements** (assignments, loops, function defs, dot-sourcing, cmdlets) bounded by your sandbox/policy.
* Discard its output; return empty string to the template.
* Expose to the runspace:

  * `$vars` (your merged hashtable) — ideally **read-only** (enforce by exposing a copy + helper `Set-Var` if you want controlled mutation).
  * `$env` (inherited provider is fine).
  * (Optional) `$ctx` as a plain `PSCustomObject` for user state, if you want to steer them away from polluting global scope.
* **Sandbox** (defense-in-depth): create runspace with `InitialSessionState` that:

  * Doesn’t import modules automatically; add a **small allow-list** if you want (e.g., `Microsoft.PowerShell.Utility`).
  * Sets `LanguageMode` to `ConstrainedLanguage` when available (not bulletproof, but helps).
  * No profiles.
* Enforce timeout; on timeout, stop the pipeline and error with a snippet:
  “`ps:` timed out after N s at line x col y: `<first line of code…>`”.

---

### Parsing & integration (fits your current engine)

1. **Streaming scanner** finds a placeholder’s **inner text**.
2. **Split head from pipeline** at the first unescaped `|`. Trim both sides.
3. Route by head:

   * `expr:` → `Evaluate-SafeExpression` (no runspace); then `Apply-Filters`.
   * `exprps:` → `Evaluate-RunspaceExpression`; then `Apply-Filters`.
   * `ps:` → `Invoke-RunspaceCode`; **reject** if any filters present.
   * else → existing `var.` / `env.` heads.
4. Keep your escape rules (`\{{`, `\}}`) as they are—no `{% %}` block syntax needed, so no new escapes.

> Long code lines inside `ps:` are clunky in one line. If you want to help users without new delimiters, add **file heads** later:
> `{{ psfile:"path\script.ps1" }}` (executes and returns empty) and
> `{{ exprpsfile:"path\expr.ps1" }}` (evaluates expression from file and returns value).

---

### Implementation sketch (minimal, drop-in helpers)

##### Safe expression (AST allow-list outline)

~~~powershell
using namespace System.Management.Automation.Language

function Test-IsSafeExprAst {
  param([Ast]$Ast, [switch]$AllowRunspaceVars)  # Allow $a in Full mode only
  switch ($Ast) {
    { $_ -is [ScriptBlockAst] }      { return (Test-IsSafeExprAst $_.EndBlock.Statements[0].Pipeline $AllowRunspaceVars) }
    { $_ -is [PipelineAst] }         { return ($_.PipelineElements.Count -eq 1) -and (Test-IsSafeExprAst $_.PipelineElements[0] $AllowRunspaceVars) }
    { $_ -is [CommandExpressionAst] }{ return (Test-IsSafeExprAst $_.Expression $AllowRunspaceVars) }
    { $_ -is [ParenExpressionAst] }  { return (Test-IsSafeExprAst $_.Pipeline $AllowRunspaceVars) }
    { $_ -is [BinaryExpressionAst] } { return (Test-IsSafeExprAst $_.Left $AllowRunspaceVars) -and (Test-IsSafeExprAst $_.Right $AllowRunspaceVars) -and
                                              ($_.Operator -in @('Add','Subtract','Multiply','Divide','Modulus','Ieq','Ine','Ilt','Igt','Ile','Ige')) }
    { $_ -is [UnaryExpressionAst] }  { return ($_.TokenKind -in @('Minus','Plus','Not')) -and (Test-IsSafeExprAst $_.Child $AllowRunspaceVars) }
    { $_ -is [ConstantExpressionAst] } { return $true }
    { $_ -is [ArrayLiteralAst] }     { return @($_.Elements | ForEach-Object { Test-IsSafeExprAst $_ $AllowRunspaceVars }) -notcontains $false }
    { $_ -is [IndexExpressionAst] }  { return (Test-IsSafeExprAst $_.Target $AllowRunspaceVars) -and (Test-IsSafeExprAst $_.Index $AllowRunspaceVars) }
    { $_ -is [MemberExpressionAst] } {
        if ($_.Static) { return $false }                               # no [Type]::Member
        if (-not ($_.Member -is [StringConstantExpressionAst])) { return $false }
        # property access only; forbid InvokeMemberExpressionAst (methods)
        return (Test-IsSafeExprAst $_.Expression $AllowRunspaceVars)
    }
    { $_ -is [VariableExpressionAst] } {
        $name = $_.VariablePath.UserPath
        if ($name -in @('vars','env')) { return $true }
        return $AllowRunspaceVars.IsPresent -and ($name -match '^[A-Za-z_][A-Za-z0-9_]*$')
    }
    default { return $false }
  }
}

function Evaluate-SafeExpression {
  param(
    [string]$Text,
    [hashtable]$Vars,
    [ValidateSet('Safe','Full')] [string]$Mode = 'Safe',
    [System.Management.Automation.Runspaces.Runspace]$SharedRunspace  # only used when Mode=Full and you want to read $a
  )
  $tokens=$null; $errors=$null
  $ast = [Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
  if ($errors -and $errors.Count) { throw "Invalid expression: $($errors[0].Message)" }

  $allowRunspaceVars = ($Mode -eq 'Full' -and $SharedRunspace)
  if (-not (Test-IsSafeExprAst $ast -AllowRunspaceVars:$allowRunspaceVars)) {
    throw "expr: contains disallowed construct."
  }

  if ($allowRunspaceVars) {
    # Evaluate via the shared runspace (still a pure expression), then Out-String/trim
    $ps = [PowerShell]::Create().AddScript($Text).AddCommand('Out-String')
    $ps.Runspace = $SharedRunspace
    $result = ($ps.Invoke() -join '') -replace '\r?\n$',''
  } else {
    # Optional ultra-safe mode: interpret the AST yourself instead of running it.
    # For now, compile-evaluate in a transient constrained runspace with only $vars, $env.
    $iss=[Runspaces.InitialSessionState]::CreateDefault(); $iss.Commands.Clear(); $iss.LanguageMode='ConstrainedLanguage'
    $rs=[Runspaces.RunspaceFactory]::CreateRunspace($iss); $rs.Open()
    $rs.SessionStateProxy.SetVariable('vars',$Vars); $rs.SessionStateProxy.SetVariable('env',$ExecutionContext.SessionState.PSVariable.GetValue('env'))
    $ps=[PowerShell]::Create().AddScript($Text).AddCommand('Out-String'); $ps.Runspace=$rs
    $result=($ps.Invoke() -join '') -replace '\r?\n$',''
    $rs.Close()
  }
  return $result
}
~~~

##### Runspace helpers (Full mode)

~~~powershell
### Create once per expansion (when Mode=Full)
function New-TemplateRunspace {
  param([hashtable]$Vars,[string]$WorkingDir)
  $iss=[Runspaces.InitialSessionState]::CreateDefault()
  # Keep Utility, Management if you want; otherwise clear and add specific cmdlets.
  # $iss.Commands.Clear()
  $iss.Variables.Clear()
  $iss.LanguageMode='FullLanguage'   # consider ConstrainedLanguage if applicable
  $rs=[Runspaces.RunspaceFactory]::CreateRunspace($iss)
  $rs.Open()
  if ($WorkingDir) { $rs.SessionStateProxy.Path.SetLocation($WorkingDir) }
  $rs.SessionStateProxy.SetVariable('vars',$Vars)
  $rs.SessionStateProxy.SetVariable('env',$ExecutionContext.SessionState.PSVariable.GetValue('env'))
  return $rs
}

function Evaluate-RunspaceExpression {
  param([Runspaces.Runspace]$Runspace,[string]$Text,[int]$TimeoutSeconds=5)
  $ps=[PowerShell]::Create().AddScript($Text).AddCommand('Out-String'); $ps.Runspace=$Runspace
  $async=$ps.BeginInvoke()
  if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) { $ps.Stop(); throw "exprps: timed out after $TimeoutSeconds s." }
  $result=($ps.EndInvoke($async) -join '') -replace '\r?\n$',''
  return $result
}

function Invoke-RunspaceCode {
  param([Runspaces.Runspace]$Runspace,[string]$Text,[int]$TimeoutSeconds=5)
  $ps=[PowerShell]::Create().AddScript($Text); $ps.Runspace=$Runspace
  $async=$ps.BeginInvoke()
  if (-not $async.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))) { $ps.Stop(); throw "ps: timed out after $TimeoutSeconds s." }
  [void]$ps.EndInvoke($async)   # discard output
  return ''                     # empty string into the template
}
~~~

---

### Pester cases to add for your design

* **Mode gating**

  * Disabled → any of the three heads: clear error messages
  * Safe → `expr:` ok; `exprps:`/`ps:` error
  * Full → all ok

* **Shared context**

  ~~~text
  {{ ps: $a = 1; $b = 2 }}
  {{ expr: $a + $b }}           # in Full mode, allowed to read runspace vars? (your choice)
  {{ exprps: $a + $b }}         # always allowed (Full)
  ~~~

* **Filters behavior**

  * `{{ ps: $x = 1 | trim }}` → error: filters not allowed after `ps:`
  * `{{ exprps: (Get-Date) | year }}` (if you have a `year` filter) → ok

* **Timeout**

  * `{{ ps: Start-Sleep 3 }}` with 1s timeout → error

* **Output shaping**

  * `{{ exprps: "a`n" }}\` → becomes “a” (final NL trimmed)

* **Safety for `expr:`**

  * Reject method call, type literal, pipeline, scriptblock.

---

### Bottom line

Your three-head plan is solid and easy to explain:

* **`expr:`** = safe, side-effect-free value
* **`exprps:`** = Full PS expression (value)
* **`ps:`** = Full PS statements (side-effects), no value

Tie them to a single `-ExpressionMode` knob, keep `expr:` fast and validated, and run `exprps:`/`ps:` in a single shared runspace with timeout limits. This fits your current architecture with minimal changes and leaves you room to add niceties later (e.g., `psfile:`).

---
---
---

## Idea: Nesting Placeholders in Code Blocks (and Eventually Expressions)

This direction is clean and it plays to the strengths of the existing template layer.

## Recommendations

* Keep **three heads**:
  `{{ expr: ... }}` (safe, value), `{{ exprps: ... }}` (full PS, value), `{{ ps: ... }}` (full PS, **no value**; side-effects only).
* **Do not inject `$vars`** into the runspace by default. Instead, let code consume **nested placeholders** inside `ps:` / `exprps:`. This gives you:

  * strict separation between “template data” and “language runtime”,
  * the ability to **filter/sanitize** injected values with your existing filters,
  * portability if you ever add another language later.
* Allow **one level** of nesting **only inside `ps:` and `exprps:` bodies** (not in heads, not in outer filter names/args). Keep it simple and unambiguous.
* In **Safe** mode, only `expr:` is allowed (no nesting needed there). In **Full** mode, `ps:` and `exprps:` are enabled and can use nested placeholders.

---

## Why nested placeholders inside code is a good idea

* **Cleaner interface:** the template layer owns data and transformations (`var.*`, `env.*`, filters). The code layer just sees **already-rendered literals**—no `$vars` coupling.
* **Targeted sanitization:** you can apply the right filter *at injection points*, e.g. path normalization, PowerShell-string quoting, etc.
* **Predictable evaluation order:** outer template pass expands inner placeholders **before** executing the code—no surprises.

---

## Must-have guardrails (to avoid “template → code injection”)

Because you’ll be splicing text into PowerShell code, require or strongly encourage filters that produce **valid PS tokens**:

* `psstring` — single-quoted string literal; escapes `'` → `''`.
  Example: `{{ var.ApiKey | psstring }}` → `'s3cr''et'`
* `as:int`, `as:double`, `as:bool` — validate & render as numeric/bool literal (error if invalid).
* `psarray` — from a list/array var: `@('a','b','c')` (each element `psstring`’d).
* `pshashtable` — from key/value pairs (each key `psstring`, values as selected type).
* (Optional) `psident` — validate as a **safe identifier** (letters, digits, `_`).

> Policy: in **Strict** mode, require one of these “PS token” filters on any nested placeholder inside code; otherwise **default** to `psstring` (safer default), or error if you prefer explicitness.

You already have a rich filter set (C#/Java/XML/URL). Adding this tiny “PS family” is very aligned with your design.

---

## Where to allow nesting (and where not)

* ✅ **Allowed**: inside the **body** of `ps:` and `exprps:` placeholders, exactly one level deep.
* ❌ **Not allowed**:

  * in the **head** of any placeholder,
  * in **filter names** of the outer placeholder,
  * inside **outer filter arguments** (keeps parsing simple and readable).

This is easy to communicate and avoids hairy ambiguities.

---

## Execution model & examples

### Single shared context (Full mode)

* Create **one runspace per template** in Full mode. Every `ps:`/`exprps:` runs there. Variables you set persist:

~~~text
{{ ps: $pi = [Math]::PI; $a = [Math]::Sin( {{ var.AngleDeg | as:double }} * $pi / 180 ) }}
The first number is {{ expr: 3 *  $a }}        # Safe expr can read $a? (see note)
The second is {{ exprps: [Math]::Exp(3 * $a) }} # Always can, Full mode
~~~

> **Choice:** keep `expr:` strictly “safe” and **not** allowed to reference `$a` (my recommendation). If you do want `expr:` to read runspace vars in Full mode, make it opt-in (e.g., `-ExpressionMode Full -ExprSafeAllowRunspaceVars`) and still validate AST tightly (no methods/pipelines/types).

### Injecting template data into code with filters

~~~text
{{ ps: 
    $name   = {{ var.UserName      | psstring }}
    $limit  = {{ var.MaxItems      | as:int   }}
    $base   = {{ var.BaseUrl       | psstring }}   # or | urlencode if building URIs inside the code
    $folder = {{ var.OutputFolder  | pathwin | psstring }}
}}
~~~

This is readable, explicit, and safe.

---

## Implementation plan (minimal changes)

1. **Add a nesting pass for code bodies**

   * In your streaming callback, when head is `ps:` or `exprps:`:

     * Extract the **body** text `code`.
     * Run a **single nested expansion** over `code`:

       * Reuse `Expand-PlaceholdersStreaming` recursively with:

         * `MaxDepth = 1`
         * **Allowed heads** = `var`, `env`, `expr` (and optionally `exprps`),
           but **disallow `ps`** inside (prevents recursion soup).
         * If `Strict` or a separate `-TemplateInjectionStrict` is on, **require** a PS-token filter (e.g., `psstring` / `as:int`) on each nested placeholder in code; else default to `psstring`.
     * Execute the resulting `code'` in the shared runspace (for `ps:` discard output; for `exprps:` capture and stringify).
   * Keep your current escape rules (`\{{`, `\}}`)—no `{% %}` blocks, so no new escapes.

2. **Add tiny new filters**

   * `psstring`, `as:int`, `as:double`, `as:bool`, `psarray`, `pshashtable`, `psident`.
   * These are straightforward and largely mirror your existing encode/convert filters.

3. **Mode gating**

   * `-ExpressionMode Disabled|Safe|Full`:

     * Disabled → all three heads error.
     * Safe → only `expr:`; nested placeholders inside `ps:`/`exprps:` never run because those heads are blocked.
     * Full → all allowed; one shared runspace per expansion; `expr:` remains safe.

4. **Error UX**

   * “`ps:` not allowed in Safe mode.”
   * “Nested placeholder in code must render a valid PowerShell token (use `psstring` / `as:int`); got: `<sample>`.”
   * “`expr:` contains disallowed construct ‘\[Type]::…’. Use `exprps:` or enable Full mode.”

---

## Performance notes

* One nested expansion pass per `ps:`/`exprps:` is cheap relative to executing PowerShell. Your streaming scanner is already efficient.
* Keeping `expr:` outside the runspace keeps Safe mode **fast**.

---

## Open questions to decide (and document)

* Should `expr:` be allowed to **read** runspace variables set by `ps:`?
  My recommendation: **No** (keeps the “safe tier” totally separate). Use `exprps:` when you want to interact with code state.
* Default behavior for nested placeholders inside code **without** PS-token filters:

  * **Option A (safe default):** implicitly wrap as `psstring`.
  * **Option B (explicit):** require a PS-token filter in Strict mode, else warn/allow. I prefer **A** + a `-Strict` that enforces explicit filters.

---

## Tiny Pester tests to add (just the new bits)

* **Gating:**

  * Safe mode: `{{ ps: $x=1 }}` → error; `{{ exprps: 1+1 }}` → error.
  * Full mode: both OK.

* **Nested injection works:**

  ~~~text
  {{ ps: $x = {{ var.A | as:int }} }}
  {{ exprps: $x + 1 }}  → "6"  (if A=5)
  ~~~

* **Implicit `psstring`:**

  ~~~text
  {{ ps: $s = {{ var.Str }} }}       # if no psstring supplied, becomes 'Str' safely
  {{ exprps: $s }}  → original text (quotes preserved as needed)
  ~~~

* **Strict requires token filters:**

  * With `-Strict`, the previous case errors until `| psstring` is added.

* **No nested `ps` inside `ps`:**

  * `{{ ps: {{ ps: $x=1 }} }}` → error “ps not allowed inside code”.

---
---

## Consideration: Prevention of Malicious Code Injection Attacks


Great instinct to pause and threat-model this. If you allow **nested placeholders** to splice values into PowerShell code, you absolutely open the door to code injection unless you put hard guardrails in place.

Here’s a practical way to keep your “nested placeholders in code” design while closing the injection holes.

### The core risk (what an attacker would do)

If a value from `-Var` (or a vars file) is injected raw into a `{{ ps: ... }}` / `{{ exprps: ... }}` body, a malicious user who can influence that value could smuggle in **extra tokens**:

~~~text
### Intended
{{ ps: $limit = {{ var.MaxItems }} }}

### If var.MaxItems = "10; Remove-Item -Recurse C:\"
### Resulting code executes both assignments and Remove-Item. Yikes.
~~~

Even with quotes, if you forget to quote correctly or allow interpolation, attackers can break out with `$(...)` or close the string and continue code.

### Guardrails that make this safe (and still ergonomic)

#### 1) One simple, opinionated rule

**Any nested placeholder inside `ps:` or `exprps:` is treated as *data*, not code.**
Concretely:

* Default behavior is to emit a **single PowerShell token** of an allowed kind:

  * string literal
  * integer/float literal
  * boolean literal
  * array/hashtable literal (only via dedicated filters)
* If the expansion would produce *anything else*, reject at template time.

This keeps the code you run syntactically sane, even if a value is hostile.

#### 2) Provide “tokenizing” filters and make them the default

Add a tiny set of “PS-safe” filters; default to `psstring` if none is specified:

* `psstring` — single-quoted PS string; escapes `'` → `''`.
  `X{{ var.Name | psstring }}Y` → `X'Bob O''Brien'Y`
* `as:int`, `as:double`, `as:bool` — validate and render as numeric/bool literals (error if invalid).
* `psarray` — from a template array: `@('a','b','c')` (each item `psstring`’d).
* `pshashtable` — from a key/value map: `@{k1='v1';k2='v2'}` (keys `psstring`, values typed by nested filters).
* `psident` — validates a **safe identifier** (letters/digits/underscore). Use sparingly.

##### Strictness knobs

* **Strict (recommended default for code):** require one of the tokenizing filters; if none provided, auto-apply `psstring`. (Documented as: “values are quoted by default”.)
* **Ultra-Strict:** *require* an explicit tokenizing filter; error if omitted.

#### 3) Verify the injection points with the PS tokenizer (belt & suspenders)

Even with filters, add a **verification pass**:

* Before you execute a `ps:`/`exprps:` body:

  1. Replace each nested placeholder with a **sentinel** (e.g., `__INJ_{GUID}__`).
  2. Tokenize the code with PowerShell’s parser (`[System.Management.Automation.Language.Parser]::ParseInput()`).
  3. Ensure each sentinel maps to a **single token** and that token’s **type is allowed** (StringConstant, Number, Variable (only if `psident`), etc.).
  4. Substitute the tokenized expansion (from filters) back for the sentinel and execute.

If any sentinel would span multiple tokens or produce a disallowed token type, you fail safe with a clear error:

> Nested placeholder must render a single PowerShell token (string/number/bool/array/hashtable). Got: `<preview…>`.

This closes the gap where someone sneaks in `;`, `` ` ``, `$(`, or `"` to open new tokens.

#### 4) Keep `expr:` entirely out of the runspace

* `expr:` remains your **safe mini-language** and never splices into PS or runs inside the PS runspace. No code injection vector there.
* In **Full** mode, let `exprps:` read variables set by `ps:`; **do not** let `expr:` do that (keeps the safe tier truly isolated).

#### 5) Sandbox + timeouts still matter

The above prevents template-data injection, but people can still write dangerous PowerShell in `ps:`/`exprps:` *on purpose*. Keep your “Full mode” sandbox:

* New isolated runspace per template.
* No profiles, no auto-imported modules; **optionally** load a small allow-list.
* Apply **timeout** per `ps:`/`exprps:` block.
* Cap **output size** (truncate with a note).
* Consider `LanguageMode = ConstrainedLanguage` when feasible (defense-in-depth; not a silver bullet).

### How this fits your current engine

##### Where to enforce

* In the `{{ ps: ... }}` / `{{ exprps: ... }}` path of your streaming callback:

  1. Extract `body`.
  2. Run **one nested expansion** on `body` (only `var`, `env`, `expr` allowed; not `ps`).
  3. If a nested placeholder inside the code has **no tokenizing filter**, either:

     * auto-apply `psstring` (default), or
     * error in Ultra-Strict.
  4. Run the **tokenizer verification** using sentinels → must be single allowed token per injection.
  5. Execute (discard output for `ps:`, capture and stringify for `exprps:`).

##### Example (safe by default)

~~~text
{{ ps:
  $name   = {{ var.UserName }}               # becomes 'Alice A.'
  $limit  = {{ var.MaxItems | as:int   }}    # becomes 42
  $folder = {{ var.OutFolder | pathwin | psstring }}  # 'C:\files\out'
}}

The year is {{ exprps: (Get-Date).Year }}.
~~~

Even if `UserName` contains malicious text, it’s just a string literal in code.

##### Example (blocked)

~~~text
{{ ps: $x = {{ var.Raw }} }}
### If Raw = "1; Remove-Item -Recurse C:\", verification sees that the
### injected text would span multiple tokens (NumberToken ';' Identifier...), so it fails.
~~~

### Extra safety: “taint tracking” (optional)

If you want belt-and-suspenders at the **value** level:

* Mark values from `-Var`, `-Variables`, `-VarsFile` as **tainted**.
* Tokenizing filters **untaint** them (because they rendered to safe tokens).
* Disallow injecting tainted values into code unless they’ve gone through a tokenizing filter (or an explicit `unsafe` filter + `-AllowRawInjection`).

Implementation can be a side map `{ name -> tainted? }` or a wrapper object; you don’t need full dataflow analysis.

### What to document (to avoid surprises)

* “`ps:` and `exprps:` allow one level of nested placeholders in their **bodies**. Those nested values are treated as **data**, rendered into **valid PowerShell tokens** via tokenizing filters (default `psstring`).”
* “Filters after `ps:` are not allowed (no output).”
* “`expr:` is a safe expression language; it cannot reference variables created in `ps:`. Use `exprps:` when you need to read from code.”
* Clear errors with line/column when a nested placeholder is missing a tokenizing filter (in strict mode) or would create multiple tokens.

### Tiny code sketch for verification

~~~powershell
using namespace System.Management.Automation.Language

function Test-InjectionIsSingleToken {
  param([string]$Code, [hashtable]$Map)  # Map: sentinel -> renderedReplacement

  # Replace each rendered value with a unique sentinel BEFORE tokenizing
  $sentinelMap = @{}
  $codeWithSentinels = $Code
  foreach ($k in $Map.Keys) {
    $g = "__INJ_$([guid]::NewGuid().ToString('N'))__"
    $sentinelMap[$g] = $Map[$k]
    $codeWithSentinels = $codeWithSentinels -replace [regex]::Escape($k), [regex]::Escape($g)
  }

  $tokens=$null; $errors=$null
  [Parser]::ParseInput($codeWithSentinels, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count) { throw "Invalid PowerShell code: $($errors[0].Message)" }

  foreach ($g in $sentinelMap.Keys) {
    $hits = $tokens | Where-Object { $_.Text -eq $g }
    if ($hits.Count -ne 1) { return $false }
    switch ($hits[0].Kind) {
      'StringExpandableToken' { }  # ok (here-string/expandable, but you’ll render single-quoted)
      'StringLiteralToken'    { }  # ok
      'NumberToken'           { }  # ok
      'VariableToken'         { }  # only if you allowed psident → variables
      default { return $false }
    }
  }
  return $true
}
~~~

*(In practice you won’t literally `-replace` the rendered value; you’ll insert sentinels at the locations where nested placeholders were, then associate them with the to-be-inserted rendered tokens.)*

---

#### Bottom line

* Yes, nested placeholders inside code **can** be a code-injection vector if raw values are spliced in.
* You can eliminate that risk without giving up the feature by:

  1. **Tokenizing filters** (`psstring`, `as:int`, …) with a **safe default**,
  2. A **tokenizer verification** pass that guarantees each injection becomes **exactly one allowed token**, and
  3. Keeping `expr:` outside the runspace (no code path from data → code there).

---
---

## Small “Tokenizing Tilter” Implementations (psstring, as:int, etc.) and a Minimal Test-InjectionIsSingleToken Wired into ps:/exprps: path

Awesome—here are the **ready-to-paste implementations** you asked for:

* A tiny set of **“tokenizing” filters** that turn values into **valid, single PowerShell tokens** (`psstring`, `asint`, `asdouble`, `asbool`, `psident`, `psarray`, `pshashtable`).
* A **validator** you can call to ensure an injected string is **exactly one allowed PS token** (belt & suspenders).
* A **drop-in snippet** showing how to apply/validate these when you expand **nested placeholders inside `ps:` / `exprps:`** bodies.

> I’ve kept names simple (`asint`/`asdouble`/`asbool`). If you prefer `as:int`/`as:double`/`as:bool` as *args* to an `as` filter, you can trivially adapt the `Apply-Filters` cases (see note in the switch).

---

### 1) Helpers: convert values to safe PS tokens

Paste these **once** (near your other helper functions):

~~~powershell
### region --- PS token helpers ---

function ConvertTo-PSStringLiteral {
  [CmdletBinding()] param([AllowNull()][object]$Value)
  $s = [string]$Value
  # Single-quoted PowerShell string: escape ' as '' (two single quotes)
  return "'" + $s.Replace("'", "''") + "'"
}

function ConvertTo-PSIdentifier {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Value)
  if ($Value -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
    throw "psident: '$Value' is not a valid PowerShell identifier."
  }
  return $Value
}

function ConvertTo-PSIntLiteral {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Value)
  $n = 0
  if (-not [int]::TryParse($Value, [System.Globalization.NumberStyles]::Integer,
      [System.Globalization.CultureInfo]::InvariantCulture, [ref]$n)) {
    throw "asint: '$Value' is not a valid integer."
  }
  return $n.ToString([System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-PSDoubleLiteral {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Value)
  $d = 0.0
  if (-not [double]::TryParse($Value, [System.Globalization.NumberStyles]::Float,
      [System.Globalization.CultureInfo]::InvariantCulture, [ref]$d)) {
    throw "asdouble: '$Value' is not a valid floating-point number."
  }
  if ([double]::IsNaN($d) -or [double]::IsInfinity($d)) {
    throw "asdouble: '$Value' must be a finite number."
  }
  # Use invariant culture with "R" (round-trip) for safety
  return $d.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
}

function ConvertTo-PSBoolLiteral {
  [CmdletBinding()] param([Parameter(Mandatory)][string]$Value)
  switch -Regex ($Value.Trim()) {
    '^(true|1|yes|on)$'  { return '$true'  }
    '^(false|0|no|off)$' { return '$false' }
    default { throw "asbool: '$Value' is not a valid boolean (true/false/1/0/yes/no/on/off)." }
  }
}

function ConvertTo-PSArrayLiteral {
  [CmdletBinding()] param([AllowNull()][object]$Value)
  # Accept arrays, lists, or scalars → wrap scalars as single-element arrays
  $items = @()
  if ($null -eq $Value) { $items = @() }
  elseif ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    foreach ($x in $Value) { $items += ,(ConvertTo-PSStringLiteral $x) }
  } else {
    $items = ,(ConvertTo-PSStringLiteral $Value)
  }
  return '@(' + ($items -join ', ') + ')'
}

function ConvertTo-PSHashtableLiteral {
  [CmdletBinding()]
  param(
    [AllowNull()][object]$Value,
    [string]$KeyValueSeparator = '='  # if a string is provided, allow simple "k=v" lines
  )
  $pairs = New-Object System.Collections.Generic.List[string]

  if ($Value -is [hashtable]) {
    foreach ($k in $Value.Keys) {
      $keyTok = ConvertTo-PSStringLiteral ([string]$k)
      $valTok = ConvertTo-PSStringLiteral ($Value[$k])
      [void]$pairs.Add("$keyTok=$valTok")
    }
  }
  elseif ($Value -is [System.Collections.IDictionary]) {
    foreach ($k in $Value.Keys) {
      $keyTok = ConvertTo-PSStringLiteral ([string]$k)
      $valTok = ConvertTo-PSStringLiteral ($Value[$k])
      [void]$pairs.Add("$keyTok=$valTok")
    }
  }
  elseif ($Value -is [string]) {
    # Parse simple "k=v" lines
    $lines = $Value -split "(\r?\n)+"
    foreach ($ln in $lines) {
      if (-not $ln) { continue }
      $idx = $ln.IndexOf($KeyValueSeparator)
      if ($idx -lt 0) { throw "pshashtable: line '$ln' is missing '$KeyValueSeparator'." }
      $k = $ln.Substring(0, $idx).Trim()
      $v = $ln.Substring($idx + $KeyValueSeparator.Length).Trim()
      $keyTok = ConvertTo-PSStringLiteral $k
      $valTok = ConvertTo-PSStringLiteral $v
      [void]$pairs.Add("$keyTok=$valTok")
    }
  }
  else {
    throw "pshashtable: expected hashtable/dictionary or 'key=value' lines, got [$($Value.GetType().FullName)]."
  }

  return '@{' + ($pairs -join '; ') + '}'
}

### endregion
~~~

---

### 2) Extend `Apply-Filters` with tokenizing filters

Find your `Apply-Filters` function’s `switch ($filterName)` and add these **cases**
(keep the style consistent with your file; `continue` assumes you loop filters left→right):

~~~powershell
### --- Tokenizing filters for PS code injection safety ---

'psstring' {
  $val = ConvertTo-PSStringLiteral $val
  continue
}

'psident' {
  $val = ConvertTo-PSIdentifier $val
  continue
}

### asint / asdouble / asbool  (explicit names)
'asint'    { $val = ConvertTo-PSIntLiteral    ([string]$val); continue }
'asdouble' { $val = ConvertTo-PSDoubleLiteral ([string]$val); continue }
'asbool'   { $val = ConvertTo-PSBoolLiteral   ([string]$val); continue }

### Optional: 'as:type' style
'as' {
  if (-not $args -or -not $args[0]) { throw "as: requires a type argument (int|double|bool)." }
  switch ($args[0].ToLowerInvariant()) {
    'int'    { $val = ConvertTo-PSIntLiteral    ([string]$val) }
    'double' { $val = ConvertTo-PSDoubleLiteral ([string]$val) }
    'bool'   { $val = ConvertTo-PSBoolLiteral   ([string]$val) }
    default  { throw "as: unsupported type '$($args[0])'. Supported: int, double, bool." }
  }
  continue
}

'psarray' {
  # If the current value is a JSON string or similar, you could detect/parse here;
  # this basic version string-quotes each element.
  $val = ConvertTo-PSArrayLiteral $val
  continue
}

'pshashtable' {
  $val = ConvertTo-PSHashtableLiteral $val
  continue
}
~~~

> ✅ With just this, template authors can write `{{ var.Name | psstring }}`, `{{ var.N | asint }}`, etc., and be sure what lands in code is a **single, safe PS token**.

---

### 3) Verifier: “is exactly one allowed PS token?”

Paste this anywhere (e.g., near helpers). Use it when you expand **nested** placeholders for `ps:`/`exprps:` bodies.

~~~powershell
using namespace System.Management.Automation.Language

function Test-IsSingleAllowedPSToken {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$Text,
    [string[]]$AllowedTokenKinds = @('StringLiteralToken','StringExpandableToken','NumberToken','VariableToken')
  )
  $tokens = $null; $errors = $null
  [Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors -and $errors.Count) { return $false }

  # Filter out trivia tokens
  $meaningful = $tokens | Where-Object {
    $_.Kind -notin @('NewLine','EndOfInput','LineContinuation','Comment') -and $_.Text -ne ''
  }

  if ($meaningful.Count -ne 1) { return $false }
  return ($meaningful[0].Kind -in $AllowedTokenKinds)
}
~~~

---

### 4) Where/how to enforce this for **nested** placeholders in code

You said you’ll allow **one level** of nesting **inside** `{{ ps: ... }}` and `{{ exprps: ... }}` bodies. Here’s a small, **self-contained** helper you can call *after* you extract the code **body** and run one nested expansion pass:

~~~powershell
function Normalize-And-Validate-NestedTokens {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$CodeAfterNested,
    [switch]$StrictInjection = $true   # if set, require tokenizing filters; else default to psstring when needed
  )

  # Minimal heuristic: if author forgot a tokenizing filter and $StrictInjection is off,
  # quote "bare" chunks to psstring automatically. A safe default that avoids code injection.
  # We’ll keep this very conservative: only quote segments that are NOT already valid single tokens.

  # Token test: if whole string is a single allowed token, we're fine.
  if (Test-IsSingleAllowedPSToken -Text $CodeAfterNested) {
    return $CodeAfterNested
  }

  if ($StrictInjection) {
    throw "Nested placeholder in code must render a single PowerShell token (use psstring/asint/asdouble/asbool/psarray/pshashtable). Offending text: $CodeAfterNested"
  }

  # Non-strict path: fallback to a single-quoted PS string literal
  return ConvertTo-PSStringLiteral $CodeAfterNested
}
~~~

##### Where to call it

Inside your **`ps:` / `exprps:`** handler:

1. Extract `body` (the code).
2. Run a **one-level nested expansion** on `body` (allowing `var`, `env`, `expr`—and **not** `ps`).
3. **Normalize/validate** the result:

   ~~~powershell
   $codeSafe = Normalize-And-Validate-NestedTokens -CodeAfterNested $nestedExpanded -StrictInjection:$Strict
   ~~~
4. Execute:

   * `ps:` → run `$codeSafe` in your shared runspace, **discard** output (empty string to template).
   * `exprps:` → run `$codeSafe` and **capture** expression result (then filters apply).

> If you already know *which* substrings came from nested placeholders (because you expand each placeholder via a callback), you can validate **each** injected piece with `Test-IsSingleAllowedPSToken` instead of validating the entire `$CodeAfterNested`. That’s even stronger—use whichever is easier in your current code path.

---

#### Examples (what users can do now)

~~~text
### Strings and numbers are safe:
{{ ps: $name = {{ var.UserName | psstring }} }}
{{ ps: $limit = {{ var.MaxItems  | asint    }} }}

### Arrays / hashtables:
{{ ps: $list = {{ var.Items | psarray }} }}
{{ ps: $map  = {{ var.KV    | pshashtable }} }}

### Using exprps to read from shared runspace and produce a value:
{{ exprps: $limit + 1 }}

### Using expr (safe mini-language), still independent of PS runspace:
{{ expr: 1 + 2 + 3 }}
~~~

In **Strict** mode, authors must use one of the tokenizing filters for any nested placeholder inside `ps:`/`exprps:`. Otherwise, your default can be to auto-quote with `psstring` (safer default).

---

#### Notes / customization points

* If you want `expr:` (safe) to **read** runspace variables set by `ps:`, make it **opt-in** (e.g., a switch that loosens the AST allow-list) and still keep the safe rules (no methods/pipelines/types).
* If you prefer `as:int`/`as:double`/`as:bool` (argument syntax) instead of separate filter names, keep the `'as'` case and drop the explicit ones.
* If you ever allow `psident` to produce a `$variable` token **instead** of a bare identifier, adjust `Test-IsSingleAllowedPSToken`’s `AllowedTokenKinds` to include `VariableToken`. (By default, `psident` returns a bare identifier suitable for `function` names, property names in member access, etc.)

---

If you want, I can help you **wire the nested-expansion pass** for `ps:`/`exprps:` in your current streaming callback (it’s \~20–30 lines), but the pieces above will drop in cleanly and give you the safety you need.

---
---

## Dilemma: Whether to Allow Variables in Expressions

Great question—and your intuition is mostly right. Letting `{{ expr: ... }}` read variables like `$a` **doesn’t add “new” capability beyond what `{{ ps: ... }}` already has** when you’re in **Full** mode. The real issue isn’t raw *power*, it’s the **guarantees** you want from the “safe” tier and how cleanly you can enforce them.

Here’s the distilled take:

### What actually changes if `expr:` can see `$a`?

* **Security:** In Full mode you already permit `ps:`. So, *in principle*, `expr:` reading `$a` doesn’t expand the attack surface much.
* **Safety guarantees:** The *safe tier* promise (“no side effects, deterministic, data-only”) can get fuzzy if `$a` can be **any object** whose **property getters** or **formatters** might run code when accessed/stringified.
* **Complexity:** Your “safe” evaluator is simplest when it **doesn’t touch the PS runspace at all**. Reading `$a` couples it to runspace state (and to PS object behaviors).

### A clean policy that keeps both power and safety

I recommend this split:

1. **ExpressionMode = Safe**
   `expr:` **cannot** see `$a`. It only sees `vars`/`env` via your safe rules (or nested placeholders).
   ➜ Preserves the strong “no runspace, no side effects” guarantee.

2. **ExpressionMode = Full** (you already have `ps:`)
   Offer an **opt-in** switch to allow runspace vars in `expr:`:

   * `-ExprAllowRunspaceVars` (default **off**)
   * When **on**, `expr:` may reference `$a` **but still under the AST allow-list** (no methods, no pipelines, no `[Type]`).
   * To avoid accidental side effects via weird objects, don’t let `expr:` touch arbitrary PS objects. Instead, feed it a **sanitized snapshot** of runspace variables.

#### “Sanitized snapshot” (keeps `expr:` safe even in Full)

When evaluating `expr:` with `$a` access enabled:

* Build a small hashtable `$safe` from the runspace just before evaluation:

  * Allow **only primitives** (string, int, double, decimal, bool), **arrays of primitives**, and **hashtables of string→primitive**.
  * For `PSCustomObject`, include **NoteProperty** values (skip **ScriptProperty** to avoid executing getters).
  * **Reject** everything else (throw a clear error: “\$var type not allowed in expr”).
* Evaluate `expr:` **against `$safe`**, not against the live runspace.
  (Implementation-wise, inject `$a` etc. into the safe evaluator’s session from `$safe`, or interpret the AST and pull values from `$safe`.)

This way, even if `ps:` created complex or dangerous objects, `expr:` only sees **plain data**.

### Minimal ruleset (quick to implement, easy to explain)

* **Safe mode**: `expr:` sees only `vars`/`env`. No `$a`.
* **Full mode**:

  * `ps:` unrestricted (with sandbox + timeout).
  * `exprps:` unrestricted expression (with sandbox + timeout).
  * `expr:`:

    * Still uses the **AST allow-list** (no methods/pipelines/types).
    * If `-ExprAllowRunspaceVars` **off** ⇒ no `$a`.
    * If **on** ⇒ `$a` is available **only if** its value passes the **sanitizer** (primitive / arrays / plain hashtable / PSCustomObject NoteProperties). Otherwise error.

#### Why this is the sweet spot

* Keeps the **safe tier** truly predictable in Safe mode.
* Lets advanced users enjoy the convenience of `$a` in expressions in Full mode **without** turning `expr:` into a backdoor for side effects.
* Easy to document and test.

### Tiny sketch (how you’d wire it)

* At `expr:` evaluation time in Full mode:

  1. If `-ExprAllowRunspaceVars`:

     * Build `$safe` from the runspace (copy allowed variables & shapes).
     * Inject `$safe` vars into the expression evaluator’s scope.
  2. Enforce the same **AST allow-list** you already use (no methods, pipelines, `[Type]`).
  3. Evaluate and stringify with invariant culture; apply filters.

If you want, I can draft the `Get-SanitizedRunspaceVariables` helper (a dozen lines) and the tiny changes to your `Evaluate-SafeExpression` to accept an optional `$SafeVars` map.

---
---
---

## Possibility of signing template files

Signing is a great complement to the runtime safeguards. It solves a different problem (authenticity/integrity of inputs) and layers nicely with your AST/timeout/tokenization defenses (which cover runtime behavior).

Below is a compact plan we can adopt.

## What signing gives you (and what it doesn’t)

* **Gives:** assurance that a template/vars file hasn’t been altered and was authored by a trusted signer.
* **Doesn’t give:** runtime safety. A signed file can still do dangerous things if allowed; you still need your **Safe/Full** split, AST allow-list, tokenizing filters, timeouts, etc.

## Suggested policy knobs

Add to CLI:

* `-SignaturePolicy Off|Warn|Require` (default **Off**)
* `-TrustedSignerThumbprint <string[]>` (pin to specific code-signing certs)
* `-TrustedCatalogPath <path>` (signed catalog for a set of files)
* (optional) `-RequireSignedVarsFile` (disallow inline `-Var` when enforcing signatures)

Enforcement order (stop at first failure):

1. Verify **catalog** if provided (best for many files).
2. Else verify **individual signatures** (Authenticode) for signed file types.
3. Else (if **Require**) fail; if **Warn**, log a warning; if **Off**, proceed.

## Practical ways to sign & verify

### A) File Catalog (recommended for template + vars sets)

**Create once (build step):**

~~~powershell
## 1) Create catalog with SHA-256 hashes for your files
$files = @(
  'TemplateA.tmpl','TemplateB.tmpl',
  'vars.prod.psd1','vars.dev.psd1'
)
New-FileCatalog -Path (Get-Location) `
  -CatalogFilePath .\templates.cat `
  -FilesToCatalog $files `
  -CatalogVersion 2.0

## 2) Sign the catalog with a code-signing cert
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.EnhancedKeyUsageList.FriendlyName -contains 'Code Signing' } | Select-Object -First 1
Set-AuthenticodeSignature -FilePath .\templates.cat -Certificate $cert -TimestampServer http://timestamp.server.example
~~~

**Verify at runtime:**

~~~powershell
function Test-TrustedCatalog {
  param([string]$CatalogPath,[string]$RootDir,[string[]]$Files,[string[]]$TrustedThumbprints)

  # Check the catalog’s signature
  $sig = Get-AuthenticodeSignature -FilePath $CatalogPath
  if ($sig.Status -ne 'Valid' -or ($TrustedThumbprints -and $sig.SignerCertificate.Thumbprint -notin $TrustedThumbprints)) {
    throw "Catalog signature invalid or signer not trusted."
  }

  # Verify that each file matches the catalog (integrity)
  $res = Test-FileCatalog -CatalogFilePath $CatalogPath -Path $RootDir
  foreach ($f in $Files) {
    $entry = $res.Files | Where-Object { $_.Path -ieq (Join-Path $RootDir $f) }
    if (-not $entry) { throw "File '$f' not present in catalog." }
    if ($entry.Status -ne 'HashMatches') { throw "File '$f' hash mismatch (status: $($entry.Status))." }
  }
}
~~~

**When to use:** you ship multiple templates/vars; you want one thing to verify them all quickly and strongly.

### B) Authenticode on individual files

Works great for **PowerShell file types** (`.ps1`, `.psm1`, `.psd1`). It appends a signature block.

**Sign:**

~~~powershell
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.EnhancedKeyUsageList.FriendlyName -contains 'Code Signing' } | Select-Object -First 1
Set-AuthenticodeSignature -FilePath .\vars.prod.psd1 -Certificate $cert -TimestampServer http://timestamp.server.example
~~~

**Verify:**

~~~powershell
function Test-TrustedFileSignature {
  param([string]$Path,[string[]]$TrustedThumbprints)
  $sig = Get-AuthenticodeSignature -FilePath $Path
  if ($sig.Status -ne 'Valid') { throw "Signature invalid on '$Path' ($($sig.StatusMessage))." }
  if ($TrustedThumbprints -and $sig.SignerCertificate.Thumbprint -notin $TrustedThumbprints) {
    throw "Signer not trusted for '$Path'."
  }
}
~~~

**When to use:** your vars are `.psd1` (ideal), or you want to sign the script/module itself.

### C) Signed manifest (fallback for arbitrary data files)

If you have non-PS data (e.g., `.json`, `.tmpl`) and don’t want catalogs:

1. Generate a manifest file (e.g., `manifest.psd1`) listing **SHA-256** for each file.
2. **Sign the manifest** with Authenticode.
3. At runtime: verify the manifest signature, then compare `Get-FileHash` for each listed file.

This is simple and works everywhere.

## How to wire this into your engine

1. **Add parameters** (`-SignaturePolicy`, `-TrustedSignerThumbprint`, `-TrustedCatalogPath`, `-RequireSignedVarsFile`).
2. **At startup**:

   * If `TrustedCatalogPath` provided → call `Test-TrustedCatalog` for *the specific files* you’re about to read: the `-Template` file and any `-VarsFile`.
   * Else if `SignaturePolicy` is `Require`:

     * If file is `.psd1` (or `.ps1/.psm1`) → `Test-TrustedFileSignature`.
     * Else → require presence of a **signed manifest** or **catalog**; if none, fail.
   * If `SignaturePolicy` is `Warn` and verification can’t be done → emit a clear warning and continue.
3. **Optionally** block inline `-Var` when signatures are required:

   * If `-RequireSignedVarsFile` and `-Var` has values → error: “Inline `-Var` not allowed when signature enforcement is on. Use a signed `-VarsFile`.”

## Recommended defaults

* Keep default `-SignaturePolicy Off` (back-compat).
* In CI/CD or prod runs, use:

  * `-SignaturePolicy Require`
  * `-TrustedSignerThumbprint @('<thumbprint1>','<thumbprint2>')`
  * `-TrustedCatalogPath .\templates.cat`
  * `-RequireSignedVarsFile`

## Edge cases & notes

* **Environment variables** can’t be signed. Treat them as untrusted; your **tokenizing filters + injection verifier** already mitigate code-injection paths in `ps:`/`exprps:`.
* **Revocation checks:** `Get-AuthenticodeSignature` uses Windows trust policy (WinVerifyTrust). In locked-down hosts, ensure network access to OCSP/CRL or time-stamp your signatures so they remain valid after cert expiration.
* **Timestamping:** always time-stamp catalog and file signatures to preserve validity post-expiry.
* **Self-signed certs (dev):** allow via explicit thumbprint pinning only; do not allow arbitrary untrusted signatures.

## Putting it all together (flow)

1. **Verify provenance** (signatures/catalog) for `-Template`, `-VarsFile` (per policy).
2. **Load vars** (reject inline `-Var` if required).
3. **Expand template** with your **Safe/Full** execution rules (AST allow-list, tokenizing filters, timeout/output caps, shared runspace only in Full).
4. **Write output**.

This layered approach gives you **authenticity/integrity** (signing) *and* **runtime safety** (execution controls).

