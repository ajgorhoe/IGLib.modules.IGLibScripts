


This idea is about allowing ***computed values*** inside templates. Recommended are two tiers of “power,” each with its own markup so users immediately understand the risk level:

---

#### Tier 1 — Safe inline expressions (no commands)

**Markup:** `{{ expr: <expression> | filters... }}`

* Intended for simple math, string ops, property/method calls, and variable references—**no pipelines or commands**.
* Example:

  * `{{ expr: (2+2) }}` → `4`
  * `{{ expr: 'Code.exe'.ToUpper() }}` → `CODE.EXE`
  * `{{ expr: var.Title + ' (Portable)' | regq }}` → escapes quotes for `.reg`

**Rationale**: This cowers majority of “computed text” needs without letting arbitrary PowerShell code run. Implementation can validate the expression (e.g., reject `| ; & > <` and command keywords), then evaluate via a tiny evaluator or a restricted `ScriptBlock` (see notes below).

---

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

---

#### How it fits the current engine

* **Delimiters stay the same**: `{{ ... }}` for inline, and add `{% ps %}...{% endps %}` for multi-line PowerShell.
* **Filters still apply after evaluation** (like in the current placeholder syntax):
  Example: `{{ ps: (Get-Date).ToString('yyyy-MM-dd') | append:" 00:00" }}`
  Example: `{{ expr: (4*0.0283495) | append:" kg" }}`

---

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

---

#### Safety & UX recommendations

* **Disabled by default.** Require `-EnableExpressions` to allow any `ps:` or `{% ps %}` usage. Repoer error if found when disabled.
* **Timeouts.** Add `-ExpressionTimeoutSeconds 5` (or similar) so long-running code can’t hang expansion.
* **Scope.** Evaluate in an **isolated runspace** with no profile, and pass in:

  * `$vars` (your merged hashtable), `$env` (standard env), maybe a small **whitelist** of helper functions.
* **Sanitize `expr:`.** For Tier 1, reject tokens that enable commands/pipelines:

  * Disallow `| ; & > < \`n`etc., and cmdlets/keywords like`Get-`, `Invoke-`, `New-`, `Set-`, `ForEach-Object`, `Start-Process`, `;`, `|\`.
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



