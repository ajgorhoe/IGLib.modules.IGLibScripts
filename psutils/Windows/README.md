
# Windows Utility Scripts
 
[This directory](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/tree/main/psutils/Windows) of [IGLibScripts](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/) contains some useful Windows Utility scripts.

**Contents**:

* [Miscellaneous Remarks](#miscellaneous-remarks) - various helpful remarks for users and developers
  * [Remarks on RemoveTaskbar.ps1](#remarks-on-removetaskbarps1)
  * [Remarks on AddContextMenuItem.ps1](#remarks-on-addcontextmenuitemps1) - some tips for using it
* [Notes for Developers](#notes-for-developers) - contains dev. notes on possible further feature, behavior, Windows development, etc.
  * [Notes - Hiding the Taskbar](#notes---hiding-the-taskbar) - what is known about using Windows Registry and newer development in Windows that affect hiding the taskbar
  * [To Do](#notes---todo) - things that might be done in the future
  * [Possible Scripting Extensions of ExpandTemplate (the Scripting Engine)](#notes---possible-scripting-extensions-of-the-expandtemplateps1-the-template-engine)

## Quick To Do

### Quick - Documentation - To Improve

* In Examples for each script, **add a comment before each code snippet** that tells what the example does (what is the effect). For example:
~~~powershell
# Hides the taskbar; -RestartExplorer restarts the Windows Explorer, such that settings take effect.
.\HideTaskbar.ps1 -RestartExplorer
# Attempts to apply the registry changes that hide the taskbar to all users
.\HideTaskbar.ps1 -AllUsers -RestartExplorer
# Reverts the effect of the script / un-hides the taskbar (only fot the current user)
.\HideTaskbar.ps1 -Revert -RestartExplorer
~~~








## Miscellaneous Remarks

## Remarks on RemoveTaskbar.ps1

In the newer versions of Windows 11  (24H2 or higher), control over removing the taskbar via registry has changed or this possibility was removed (as well as the ability to change icon size in taskbar). The basis for the script is given in [this article](https://www.airdroid.com/uem/how-to-hide-taskbar/#part2-3) or in [this post](https://learn.microsoft.com/en-us/answers/questions/1040472/no-taskbar-on-window?orderBy=Newest).

Beside that, there are some differences between RemoveTaskbar.ps1 and HideTaskbar.ps1 when iterating over user profile (SIDs - security identifiers).

## Remarks on AddContextMenuItem.ps1

### Additional Tips for Use

The script `AddCodeToExplorerMenu.ps1` **uses** `AddContextMenuItem.ps1`, and can therefore be consulted to see how the script is used. It can also be used as template for creating s**scripts for adding specific items** to Windows Explorer's context menu.

A few optional ideas (maybe included in `AddCodeToExplorerMenu.ps1` later):

* **Show only on Shift-right-click:** add the `Extended` flag (so it appears only in the “extended”/Shift menu).
* **Limit to certain file types:** use `-AppliesTo` (e.g., only show for `.txt` or for directories).
* **Open a new VS Code window:** add `-n` to the args.
* **Add a background-only “Open VS Code here”:** use `%V` for the folder path (you already did).

Some quick copy-paste examples using the AddContextMenuItem.ps1, including how to achieve some of the above possibilities:

~~~powershell
# 1) Make the entry appear only on Shift-right-click (Files + Directories)
.\AddContextMenuItem.ps1 `
  -Title "Open with VS Code" `
  -CommandPath "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -Arguments '"%1"' `
  -Icon "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -Targets Files,Directories `
  -RestartExplorer
# Add the Extended flag
New-ItemProperty -Path "HKCU:\Software\Classes\*\shell\Open_with_VS_Code" -Name Extended -Value "" -Force | Out-Null
New-ItemProperty -Path "HKCU:\Software\Classes\Directory\shell\Open_with_VS_Code" -Name Extended -Value "" -Force | Out-Null
~~~

~~~powershell
# 2) Background-only “Open VS Code here” (no file/folder selection), new window
.\AddContextMenuItem.ps1 `
  -Title "Open VS Code here" `
  -CommandPath "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -BackgroundArguments '-n "%V"' `
  -Icon "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -Targets Background `
  -RestartExplorer
~~~

~~~powershell
# 3) Only show for certain types (e.g., .ps1 files)
# Add the menu:
.\AddContextMenuItem.ps1 `
  -Title "Open PS1 in VS Code" `
  -CommandPath "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -Arguments '"%1"' `
  -Icon "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -Targets Files `
  -RestartExplorer

# Then scope it with AppliesTo (PowerShell-only files)
New-ItemProperty -Path "HKCU:\Software\Classes\*\shell\Open_PS1_in_VS_Code" -Name "AppliesTo" -Value "System.ItemType:='.ps1'" -Force | Out-Null
~~~

If one needs this to also appear in the **new** Windows 11 condensed menu (not just “Show more options”), the Explorer needs to be wired up with Command Handler registration.

## Notes for Developers

Disabling Modern Standby (S0 mode) and enabling the Standard Sleep (S3 mode) would not work on many modern laptops (because many OEMs are disabling the S3 mode in firmware) and because of this, a PowerShell script to do this was not provided. Only the registry edit scripts were provided, the `EnableS3Standby_NormalSleep.reg` for enabling the normal sleep mode, and `DisableS0Standby_ModernStandby.reg` to disable the Modern Standby (which, if it works, may result in crashing computer when sleep mode is entered via UI or buttons / closing the lid of a laptop). Some links are in the first registry file. See also:

* [Getting back S3 sleep and disabling modern standby under Windows 10 >=2004](https://www.reddit.com/r/Dell/comments/h0r56s/getting_back_s3_sleep_and_disabling_modern/?utm_source=chatgpt.com) (Reddit)
* [Disable Modern Standby in Windows 10 and Windows 11 ](https://www.elevenforum.com/t/disable-modern-standby-in-windows-10-and-windows-11.3929/?utm_source=chatgpt.com) (ElevenForum)
* Some **General Resources for Windows Admin & Hacks**:
* [Windows 11 Tutorials (Winareo)](https://winaero.com/windows-11-tutorials/) - many useful Registry settings and other Windows hacks
* [ElevenForum List of Topics](https://www.elevenforum.com/) (topics, tutorials and hacks for Windows 11 and other computer-related)
  * E.g. useful for Win not updating any more:
    * [Win 11 updates Tutorials](https://www.elevenforum.com/tutorials/?prefix_id=17)
        * [Windows 11 Updates ?? ](https://www.elevenforum.com/t/windows-11-updates.29640/)

### Notes - Hiding the Taskbar

Script: [HideTaskbar.ps1](HideTaskbar.ps1)  
Script does currently not work: although it attempts to set the specific registry value, after verification, the value has not changed.

To verify what this specific value is, evaluate the following expression in PowerShell:

~~~PowerShell
(Get-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3" -Name Settings).Settings[8]
~~~

* Basis: from [this Reddit](https://www.reddit.com/r/AutoHotkey/comments/1buwka6/script_to_change_automatically_hide_the_taskbar/), the last link:
  * [No taskbar on Windows](https://learn.microsoft.com/en-us/answers/questions/1040472/no-taskbar-on-window?orderBy=Newest), see the last answer from Sengupta; this may actually be about completely removing the taskbar (?).
  * Or: [this post](https://www.airdroid.com/uem/how-to-hide-taskbar/#part2-3), method 3 or method 4.
* This **may be outdated** or serve a different purpose maybe, e.g. for removing the taskbar rather than auto-hiding it.

A **different approach** (editing a different registry key):

* [from this article](https://learn.microsoft.com/en-us/answers/questions/2355519/hide-or-unhide-widgets-on-taskbar-in-windows-11-in):

In Registry Editor (Win-R, regedit), go to

`Computer\HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`, set **`TaskbarDa`** to 0 for hidden, 1 for visible. Q: is this for temporarily hiding or permanently removing the taskbar?

Another variant [from here](https://www.nextofwindows.com/hide-taskbar-windows-11) (methodunder No. 3): In registy, navigate to  `Computer\HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced`, then on the right pane, right-click any space and click New, then DWORD (32-bit) Value, and name the new DWORD **`AutoHideTaskbar`**.

In UI, hide / unhide the taskbar via `Settings/Personalization/Taskbar/Taskbar Behaviors/Automatically hide the taskbar`.

### Notes - ToDo

#### Add to Context Menu

Script `AddToContextMenu.ps1`, which adds a certain command to the Explorer's context menu. For example, "Open with VS Code".

Patameters:

* **Title** (e.g. "Open with VS Code")
* **Command** (e.g. `"C:\\Users\\YourUserName\\AppData\\Local\\Programs\\Microsoft VS Code\\Code.exe" "%V"` to open directories, `"...\\Code.exe" "%1"` for files)
* **Icon** (optional) - you can set it to the path of executable, e.g. `"C:\\Users\\YourUserName\\AppData\\Local\\Programs\\Microsoft VS Code\\Code.exe"`

##### Add Open with VS Code

See:

* [How do I get Microsoft Code to come up in my right click menu?](https://learn.microsoft.com/en-gb/answers/questions/2006361/how-do-i-get-microsoft-code-to-come-up-in-my-right) (Microsoft)
* [Visual Studio Code "Open With Code" does not appear after right-clicking a folder](https://stackoverflow.com/questions/37306672/visual-studio-code-open-with-code-does-not-appear-after-right-clicking-a-folde)

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




