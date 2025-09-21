
# PowerShell Template Engine (ExpandTemlate.ps1) - Expressions and Code Blocks

This contains the **final proposal** for adding **expressions and code blocks** to the templatee engine.

---
---

## Proposal: Expressions & Code Blocks for the PowerShell Template Engine

> **Status:** Draft
> **Audience:** Template engine maintainers & contributors
> **Scope:** Add first-class support for expressions and code blocks with strong safety guarantees, predictable output semantics, and minimal impact on existing templates.

---

### 1) Overview

We introduce three new placeholder **heads**:

* `{{ expr: ... }}` – **safe expression** (no side effects). Produces a value that can be passed through existing filters.
* `{{ exprps: ... }}` – **full PowerShell expression** (runs in a sandboxed runspace). Produces a value that can be filtered.
* `{{ ps: ... }}` – **full PowerShell code block** (statements, side effects). **Produces no value**; the placeholder renders as an empty string.

We use a single mode knob to gate features:

~~~
-ExpressionMode Disabled|Safe|Full    # default: Disabled
~~~

* **Disabled:** none of the new heads are allowed (unchanged behavior for existing templates).
* **Safe:** only `expr:` is allowed.
* **Full:** `expr:`, `exprps:`, and `ps:` are all allowed.

Additional controls:

~~~
-ExpressionTimeoutSeconds <int>   # applies to exprps:/ps: (default suggestion: 5)
-ExpressionMaxOutputKB <int>      # trims huge outputs with a note (default suggestion: 256)
-ExpressionWorkingDir <path>      # default: template’s folder
-ExprAllowRunspaceVars            # (Full mode) allow expr: to read sanitized runspace variables
~~~

The **streaming scanner** remains the engine’s main loop; no regex path is required.

---

### 2) Goals & Non-Goals

#### Goals

* Add computed values and side-effectful setup steps without changing how variables/filters work today.
* Keep the **safe tier** (`expr:`) fast, isolated, and predictable.
* Provide a **Full** tier (`exprps:`, `ps:`) with timeouts, sandboxing, and explicit data injection points.
* Preserve backward compatibility: by default, nothing changes.

#### Non-Goals

* No new `{% ... %}` block syntax; we avoid a second delimiter system and new escaping rules.
* No nested placeholders beyond **one level** inside `exprps:`/`ps:` bodies (keeps parsing simple).
* No silent elevation of `expr:` power (e.g., pipelines, method calls, `[Type]` literals) even in Full mode.

---

### 3) Syntax & Semantics

#### 3.1 `{{ expr: ... }}` (safe expression)

* **Allowed:** numbers/strings, parentheses, unary/binary arithmetic, comparisons, array/`[]` indexing, **property access only**, variables `$vars` and `$env`.
  (In **Full** mode, `$a` etc. from code can be read **only** if `-ExprAllowRunspaceVars` is set and variables pass sanitization; see §6.3.)
* **Disallowed:** pipelines, cmdlets, method calls (`.ToUpper()`), type expressions (`[IO.File]::...`), scriptblocks, `;`, `&`, redirection.
* **Output:** single value → string (numbers with invariant culture); then filters apply.

**Examples**

~~~
{{ expr: 2 + 2 }}                       -> 4
{{ expr: vars['User'] + ' #' + env.USERNAME }}
{{ expr: (3 * 7) | tostring }}          # filters still apply post-eval
~~~

#### 3.2 `{{ exprps: ... }}` (full PS expression)

* **Runs** in a shared sandboxed runspace (created once per expansion in **Full** mode).
* Can reference runspace variables set by previous `ps:` blocks.
* **Output:** expression result → string (trim a single trailing newline); then filters apply.
* **Subject to:** timeout, output cap, sandbox policy.

**Examples**

~~~
{{ exprps: (Get-Date).Year }}
{{ exprps: $a + 1 | tostring }}
~~~

#### 3.3 `{{ ps: ... }}` (full PS statements)

* **Runs** in the shared sandboxed runspace (Full mode).
* Side effects are allowed (per sandbox policy). Variables persist for later placeholders.
* **Output:** discarded. The placeholder is replaced with an empty string.
  **Filters are not allowed** after `ps:`; attempting to use filters produces a clear error.

**Examples**

~~~
{{ ps: $pi = [Math]::PI; $a = [Math]::Sin(60 * $pi / 180) }}
The value is {{ exprps: [Math]::Exp(3 * $a) }}
~~~

---

### 4) Evaluation Order & Nesting

* Placeholders are processed **left → right** by the streaming scanner.
* **One-level nesting** is allowed **only inside `exprps:` and `ps:` bodies**.

  * Allowed nested heads: `var.*`, `env.*`, `expr:` (and optionally `exprps:` if desired).
  * **Not allowed:** nested `ps:` inside code; nested placeholders in heads, filter names, or outer filter arguments.
* Nested placeholders inside code bodies are treated as **data** (see §5) and are expanded **before** executing the code.

**Example (data injection via nested placeholders)**

~~~
{{ ps:
  $name   = {{ var.UserName | psstring }}
  $limit  = {{ var.MaxItems  | asint    }}
  $folder = {{ var.OutDir    | pathwin | psstring }}
}}
~~~

---

### 5) Injection Safety (required)

Nested placeholders inside `exprps:`/`ps:` bodies must render **single, valid PowerShell tokens**. To make this ergonomic and safe:

#### 5.1 Tokenizing filters (new)

Add filters that render **exactly one token**:

* `psstring` – single-quoted PS string; escapes `'` → `''`
* `asint` / `asdouble` / `asbool` – numeric/bool literals with validation
* `psident` – validates a safe identifier (`[A-Za-z_][A-Za-z0-9_]*`)
* `psarray` – renders `@('a','b')` (each element `psstring`)
* `pshashtable` – renders `@{ 'k'='v'; 'k2'='v2' }`

> In **Strict** mode, require a tokenizing filter for each nested placeholder inside code; otherwise default to `psstring` (safe default).

#### 5.2 Verifier (belt & suspenders)

Before executing a code body (after nested expansion), verify that each injected piece is a **single allowed PS token** (string, number, bool, identifier). If not, **fail fast** with a clear error.

*(Implementation provided previously; summarized in §8.)*

---

### 6) Execution Model

#### 6.1 Safe expressions (`expr:`)

* Evaluated without a PS runspace (fast).
* Enforced by **AST allow-list** (see §8). If any disallowed node appears, error out.

#### 6.2 Full mode runspace (`exprps:`, `ps:`)

* A **single runspace** is created per template expansion; it is reused for all `exprps:`/`ps:` placeholders.
* **Sandbox defense-in-depth:**

  * No profiles; no automatic module import.
  * Consider `InitialSessionState` with minimal modules/cmdlets (allow-list), or at least default modules with caution.
  * `LanguageMode=ConstrainedLanguage` when feasible (not a silver bullet, but helpful).
  * **Timeout** per block; **output size cap**; optional working directory.
* Values from nested placeholders are **rendered to tokens** (using tokenizing filters) and spliced into code only after token verification.
* `ps:` output is discarded (empty string returned). `exprps:` returns the expression result.

#### 6.3 Optional: `expr:` access to runspace variables (Full mode)

* Controlled by `-ExprAllowRunspaceVars` (default off).
* When on, `expr:` may read `$a`, `$b`, etc., but:

  * Values are provided via a **sanitized snapshot** of the runspace:

    * Allowed shapes: primitive (string/int/double/decimal/bool), arrays of primitives, hashtables of string→primitive, `PSCustomObject` **NoteProperties** (skip ScriptProperties).
    * Everything else is rejected with a clear error.
  * `expr:` still obeys the **AST allow-list** (no methods/pipelines/types).

---

### 7) Output Shaping

* Numbers/DateTime: convert using **InvariantCulture**.
* For `exprps:` values and any PS textual outputs: **trim a single trailing newline**.
* `ps:` blocks **cannot** be followed by filters; if present, error:

  > `ps:` code blocks don’t produce output; filters are not allowed.

---

### 8) Implementation Notes (drop-in components)

#### 8.1 Tokenizing filters

Add cases to `Apply-Filters`:

* `psstring` → single-quoted literal with `'` doubled
* `asint` / `asdouble` / `asbool` → validated literals
* `psident` → identifier validation
* `psarray` / `pshashtable` → render literal forms

(We drafted ready-to-paste helpers and filter cases earlier. I can re-send in one block when you start coding.)

#### 8.2 Single-token verification

Implement `Test-IsSingleAllowedPSToken` using the PowerShell parser to confirm the injected text is exactly one allowed token. Use it:

* either per injected piece (preferred), or
* on the entire code after replacing each injection with a sentinel and mapping sentinels to tokens.

#### 8.3 Safe expression evaluator (`expr:`)

Parse with `[System.Management.Automation.Language.Parser]` and validate via an **AST allow-list**:

* **Allowed AST nodes:** `ConstantExpressionAst`, `UnaryExpressionAst`, `BinaryExpressionAst` (limited operators), `ParenExpressionAst`, `ArrayLiteralAst`, `IndexExpressionAst`, `MemberExpressionAst` (instance, property only), `VariableExpressionAst` (only `$vars`/`$env`; and **optionally** sanitized `$a` etc. when `-ExprAllowRunspaceVars` is set).
* **Disallowed:** `InvokeMemberExpressionAst` (methods), `TypeExpressionAst`, pipelines, scriptblocks, redirection, `;`, `&`, etc.
* On violation, error:

  > `expr:` contains disallowed construct ‘…’. Use `exprps:` or enable Full mode.

#### 8.4 Streaming integration

In your streaming callback:

1. Split head/pipeline at first unescaped `|`.
2. Route:

   * `expr:` → `Evaluate-SafeExpression` → `Apply-Filters`
   * `exprps:` → one-level nested expansion in body → verify tokens → run in runspace → `Apply-Filters`
   * `ps:` → one-level nested expansion in body → verify tokens → run in runspace → **reject** if outer filters present
   * else → existing `var.` / `env.` path
3. Keep escape rules (`\{{`, `\}}`) unchanged.

---

### 9) Error Messages & Diagnostics

* **Mode gating**

  * Disabled: `Expressions are disabled (ExpressionMode=Disabled). Found 'expr:' at line X, col Y.`
  * Safe: `Full expressions/code require ExpressionMode=Full. Found 'ps:' at line X, col Y.`
* **ps with filters**: `ps:` code blocks don’t produce output; filters are not allowed.\`
* **Timeout**: \`\`ps:` timed out after N s at line X, col Y: <first line of code…>`
* **Injection**: `Nested placeholder in code must render a single PowerShell token (use psstring/asint/asdouble/asbool/psarray/pshashtable). Offending text: …`
* **expr disallowed AST**: `expr: contains disallowed construct ‘[Type]::…’.`
* **Sanitization** (ExprAllowRunspaceVars): `$a: value of type 'System.IO.FileInfo' is not allowed in expr (only primitive/array/hashtable/NoteProperties).`

Trace (`-OutTrace`) additions:

* ` [exp] {{ expr: … }} -> "<value>" (X ms)`
* ` [exp] {{ exprps: … }} (X ms)`
* ` [run] {{ ps: … }} (X ms)`
* For code: list injected tokens with their kinds when `-OutDebug` is on.

---

### 10) Examples

**Safe mode**

~~~
{{ expr: vars['Title'] + ' v' + vars['Version'] }}
~~~

**Full mode with side effects**

~~~
{{ ps:
  $base = {{ var.BaseUrl | psstring }}
  $name = {{ var.UserName | psstring }}
  $resp = Invoke-RestMethod -Uri "$base/api/user/$name"
  $id   = $resp.id
}}

User ID: {{ exprps: $id }}
~~~

**Full mode with sanitized expr variables (if enabled)**

~~~
## With -ExprAllowRunspaceVars
{{ ps: $a = 5; $b = 8 }}
{{ expr: $a + $b }}     # Allowed via sanitized snapshot
~~~

---

### 11) Backward Compatibility

* Default `-ExpressionMode Disabled` means existing templates behave exactly as before.
* No new delimiters or escape rules; only new heads inside `{{ … }}`.
* New filters are opt-in; they don’t change existing filter semantics.

---

### 12) Test Plan (Pester)

**Mode gating**

* Disabled: any `expr:`/`exprps:`/`ps:` → error messages include line/col and required mode.
* Safe: `expr:` ok; `exprps:`/`ps:` blocked.

**Safe expr validator**

* Accept: arithmetic, comparisons, indexing, `$vars`/`$env`.
* Reject: `[Type]::…`, `.Method()`, pipelines, scriptblocks, `;`, `&`.

**Runspace**

* `ps:` persists variables used by later `exprps:`.
* Timeout: `Start-Sleep 10` with 1s limit → error.
* Output cap: emit large text → truncated.

**Injection safety**

* Without filters: values becoming single tokens → allowed (default to `psstring`).
* With `-Strict`: using `ps:` without tokenizing filters → error.
* Attempted multi-token injection (`; Remove-Item …`) → blocked by verifier.

**Error UX**

* Using filters after `ps:` → error.
* Sanitization failure for `-ExprAllowRunspaceVars` on a complex object → error.

---

### 13) Rollout Plan

1. **Phase 1 (Safe tier):**

   * Implement `expr:` with AST allow-list + tests.
   * Add `-ExpressionMode` (Disabled/Safe/Full), default Disabled.
   * Docs & examples.

2. **Phase 2 (Full tier):**

   * Implement shared runspace, `exprps:` and `ps:`.
   * Add tokenizing filters + verifier; nested one-level expansion for code bodies.
   * Add timeout/output-cap; tests (including injection tests).

3. **Phase 3 (Options & polish):**

   * Add `-ExprAllowRunspaceVars` with sanitizer.
   * Add `-ExpressionWorkingDir` and better diagnostics.
   * CI: run Pester in Safe and Full configurations.

---

### 14) Open Questions (to finalize before coding)

* Should `expr:` ever read runspace variables by default in Full mode?
  **Proposal:** No—keep as opt-in via `-ExprAllowRunspaceVars`.
* Default behavior for nested injection with no tokenizing filter:
  **Proposal:** auto-apply `psstring` (safe default), but enforce explicit filters when `-Strict` is used.
* Which modules/cmdlets (if any) to preload in the sandbox?
  **Proposal:** Start with none, document how to opt-in later.

---

Proposal for **initial implementation**:

* The **tokenizing filters** and **verifier** as a single paste-ready block,
* A minimal **AST allow-list** evaluator for `expr:`,
* The **runspace helpers** (`New-TemplateRunspace`, `Evaluate-RunspaceExpression`, `Invoke-RunspaceCode`),
* Small, composable changes to the streaming callback to wire it all together.

---
---
---





