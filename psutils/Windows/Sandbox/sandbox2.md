# Windows PowerShell Utilities — Documentation

*Last updated: 22 Aug 2025*

---

## Introduction – Windows PowerShell Utilities

These utilities make it easy to perform common Windows customization and admin tasks on a machine you own—things like:

* [Show full context menus](#showfullcontextmenusps1) (skip “Show more options”)
* [Add custom Explorer context-menu items](#addcontextmenuitemps1) (e.g., **Open with VS Code**)
* [Toggle taskbar auto-hide](#hidetaskbarps1) or manipulate advanced taskbar state ([RemoveTaskbar](#removetaskbarps1))
* [Change desktop and taskbar icon sizes](#setdesktopiconsizeps1) / [taskbar icon size](#settaskbariconsizeps1)
* A small [GUI utility](#iconsizeutilityps1) to apply sizes interactively
* A tiny [template engine](#template-engine-expandtemplateps1) to generate .reg files with placeholders

Most scripts work by adding/removing entries in the **Windows Registry**. Many provide consistent switches:

* `-Revert`
  Undo or restore the default/previous behavior (e.g., remove a tweak).
* `-RestartExplorer`
  Restarts **Windows Explorer** so changes take effect. Expect the taskbar and desktop to briefly disappear and re-appear—internally, `explorer.exe` is terminated and relaunched.
* `-AllUsers`
  Apply for **all users**:

  * If **not elevated**, the script **relaunches itself** with admin rights (UAC prompt) and a short pause so you can review output.
  * Behavior by scope:

    * For “global” keys (HKLM) → write/remove under `HKLM\Software\Classes` (or other HKLM paths as relevant).
    * For per-user keys → iterate user profiles and write under each user hive (where feasible) or at least the current user; see each script’s notes.

### Wrapper scripts & examples

* **`AddCodeToExplorerMenu.ps1`**
  Calls `AddContextMenuItem.ps1` to add **Open with VS Code** (files, folders, background), then runs `AddCode_Verify.ps1` to confirm registry state. Verbose on purpose so you can follow along.
* **Registry file examples** (manual import via double-click / `regedit.exe`):
  `AddCode_Example_WithPlaceholders.reg`, `RemoveCode.reg`, `ShowFullContextMenus.reg`, `ShowFullContextMenusRevert.reg`, `DisableS0Standby_ModernStandby.reg`, `EnableS3Standby_NormalSleep.reg`.
  These are simpler than the PowerShell versions (no elevation flow, no All-Users iteration).

### Auxiliary scripts

* **`RestartExplorer.ps1`** – restarts Explorer (handy if you don’t pass `-RestartExplorer`).
* **`IsAdmin.ps1`** – prints whether the current PowerShell session is elevated.
* **`RunAsAdmin.ps1`** – example pattern to self-elevate and re-invoke with original arguments.
* **`ExpandTemplate.ps1`** – a small template engine to generate final `.reg` files from `.tmpl` with variables/placeholders. See the [Template Engine](#template-engine-expandtemplateps1) section.

### Compatibility

Windows internals evolve. Some tweaks that worked in Windows 10 and early Windows 11 builds are throttled or ignored in newer Windows 11 releases (e.g., taskbar icon size). Scripts try to:

* **Warn** when a setting is known to be ignored on newer builds.
* **Still apply** the registry change (in case Microsoft restores support later).

> If something appears to “do nothing,” check the script’s notes below for version caveats, confirm the registry value with `regedit.exe`, and consider logging off/on if Explorer restarts don’t pick up a change.

---

## Script Reference

### `ShowFullContextMenus.ps1`

**Description**
Forces the **classic full** context menu (Windows 10-style) so you don’t need “Show more options.” Implements the `CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}` tweak.

**Parameters**

* `-Revert` – removes the CLSID override (return to condensed menu).
* `-RestartExplorer` – restart Explorer so menus update immediately.
* `-AllUsers` – applies to all users by iterating user hives; elevated if needed.

**Examples**

```powershell
.\ShowFullContextMenus.ps1 -RestartExplorer
.\ShowFullContextMenus.ps1 -AllUsers -RestartExplorer
.\ShowFullContextMenus.ps1 -Revert -RestartExplorer
```

**Notes**

* This is a **per-user** tweak. With `-AllUsers`, the script iterates SIDs and writes under each user hive (where accessible).

---

### `HideTaskbar.ps1`

**Description**
Enables Windows’ **auto-hide taskbar** setting by setting `AutoHideTaskbar` under the `Explorer\Advanced` key. `-Revert` disables auto-hide.

**Parameters**

* `-Revert` – sets `AutoHideTaskbar=0`.
* `-RestartExplorer` – restart Explorer to apply immediately.
* `-AllUsers` – sets `AutoHideTaskbar` under HKU for all loaded profiles and the current user.

**Examples**

```powershell
.\HideTaskbar.ps1 -RestartExplorer
.\HideTaskbar.ps1 -AllUsers -RestartExplorer
.\HideTaskbar.ps1 -Revert -RestartExplorer
```

**Notes**

* Works reliably across Windows 10 and Windows 11.
* When run elevated, you’ll see a short pause so you can read the elevated window’s output.

---

### `RemoveTaskbar.ps1`

**Description**
Manipulates the **`StuckRects3\Settings`** binary to aggressively hide the taskbar by toggling bit 3 (0x08) at **byte index 8**. Includes verification that the byte was written.

**Parameters**

* `-Revert` – clears the bit (restores default).
* `-RestartExplorer` – restart Explorer. Log off/on may still be required depending on build.
* `-AllUsers` – iterates other profiles. In the latest version:

  * With `-AllUsers -Revert` → removes/modifies both **HKLM** (global) **and HKCU** (current user) to keep states consistent; prints a per-hive summary.

**Examples**

```powershell
.\RemoveTaskbar.ps1 -RestartExplorer
.\RemoveTaskbar.ps1 -AllUsers -RestartExplorer
.\RemoveTaskbar.ps1 -Revert -AllUsers -RestartExplorer
```

**Notes**

* On many newer Windows 11 builds, Explorer **resets** this byte back to default after it starts, making changes transient or ignored. The script still writes and verifies the value; if you see it flip back after Explorer starts, that’s the OS enforcing the default.

---

### `SetDesktopIconSize.ps1`

**Description**
Sets desktop icon size using the standard view sizes:

| Size name    | Pixel size |
| ------------ | ---------- |
| `Small`      | 16         |
| `Medium`     | 32         |
| `Large`      | 48         |
| `ExtraLarge` | 64         |

Writes the `IconSize` value under the desktop bag (per user) and restarts Explorer if requested.

**Parameters**

* `-Size <Small|Medium|Large|ExtraLarge>` – explicit size.
  *Default behavior:* Small; `-Revert` maps to Medium.
* `-Revert` – sets Medium.
* `-RestartExplorer` – restart Explorer.
* `-AllUsers` – attempts to apply to other users by touching their hives (where possible).

**Examples**

```powershell
.\SetDesktopIconSize.ps1            # Small
.\SetDesktopIconSize.ps1 -Revert    # Medium (default)
.\SetDesktopIconSize.ps1 -Size Large -RestartExplorer
```

**Notes**

* Some Windows builds keep per-view “bag” data; the script targets the standard Desktop bag. If you’ve got custom layouts or 3rd-party shells, behavior can vary.

---

### `SetTaskbarIconSize.ps1`

**Description**
Attempts to set taskbar icon size by setting `TaskbarSi` under `Explorer\Advanced`:

| Size name | Value       |
| --------- | ----------- |
| `Small`   | 0           |
| `Medium`  | 1 (default) |
| `Large`   | 2           |

**Parameters**

* `-Size <Small|Medium|Large>` – explicit size (default Small; `-Revert` maps to Medium).
* `-Revert` – sets Medium.
* `-RestartExplorer`
* `-AllUsers`

**Examples**

```powershell
.\SetTaskbarIconSize.ps1 -Size Small -RestartExplorer
.\SetTaskbarIconSize.ps1 -Revert -RestartExplorer
```

**Compatibility & Notes**

* **Windows 11 (recent builds)** often **ignore** `TaskbarSi`. The script prints a **version warning** up front and still writes the value (in case support returns later). If you don’t see a difference after restart/logoff, that’s the OS no longer honoring the setting.

---

### `IconSizeUtility.ps1`

**Description**
A minimal **WinForms** dialog to apply icon sizes:

* **Taskbar**: `Small`, `Medium`, `Large`
* **Desktop**: `Small`, `Medium`, `Large`, `ExtraLarge`
* Buttons: **Apply** (current user), **Apply to All Users**
* A warning label appears if your Windows build likely ignores taskbar size.

**Parameters**

* None (interactive GUI). Internally restarts Explorer when you click Apply.

**Examples**

```powershell
.\IconSizeUtility.ps1
```

**Notes**

* Built for simplicity.

---

### `AddContextMenuItem.ps1`

**Description**
Create or remove a **classic Explorer context-menu item** for:

* Files (`*\shell\<KeyName>`)
* Directories (`Directory\shell\<KeyName>`)
* Folder background (`Directory\Background\shell\<KeyName>`)

Under the hood it uses the **.NET Registry API** (`Microsoft.Win32.Registry`) to avoid wildcard issues with `*\...`.

**Parameters**

* `-Title <string>` – menu caption (also written to `MUIVerb`).
* `-CommandPath <string>` – full path to the executable (quoted automatically).
* `-Arguments <string>` – default `"%1"` for Files/Directories.
* `-BackgroundArguments <string>` – default `"%V"` for Background.
* `-Icon <string>` – optional icon path.
* `-Targets <Files|Directories|Background>[]` – one or more; specifies for which objects the context menu item appears; default is `Files,Directories`.
  * `Files` - the Explorer menu item appears when right-clicking a file in Windows Explorer or a compatible application (such as Total Commander)
  * `Directories` - appears when right-clicking directories
  * `Background` - appears when right-clicking empty space in Explorer

* `-KeyName <string>` – registry key name; defaults to a safe version of the title.
* `-Revert` – remove the item instead of creating.
* `-AllUsers` – operate under **HKLM\Software\Classes** (global).
  *Note:* In the current version, \*\*`-AllUsers -Revert` also removes the **current user** entry (HKCU) for consistency.
* `-RestartExplorer`

**Examples**

```powershell
# Add for files, folders & background
.\AddContextMenuItem.ps1 `
  -Title 'Open with VS Code' `
  -CommandPath "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -Icon "$env:LOCALAPPDATA\Programs\Microsoft VS Code\Code.exe" `
  -Targets Files,Directories,Background `
  -RestartExplorer

# Remove globally (HKLM) and current user copy
.\AddContextMenuItem.ps1 `
  -Title 'Open with VS Code' `
  -CommandPath 'C:\Path\To\Code.exe' `
  -Targets Files,Directories,Background `
  -AllUsers -Revert -RestartExplorer
```

**Particularities**

* The script shows a **6-second** pause in elevated runs so you can read output.
* Strings like `${itemSubPath}` are used where a colon follows a variable in a message to avoid `$var:` parsing quirks.

---

### `AddCodeToExplorerMenu.ps1`

**Description**
A convenience wrapper that:

1. Locates VS Code (`Code.exe`) in common paths.
2. Invokes `AddContextMenuItem.ps1` to create **Open with VS Code** for **Files**, **Directories**, and **Background**.
3. Restarts Explorer if requested.
4. Runs `AddCode_Verify.ps1` to confirm the registry state.

**Parameters**

* `-AllUsers`, `-Revert`, `-RestartExplorer` (forwarded to the helper).

**Examples**

```powershell
.\AddCodeToExplorerMenu.ps1 -RestartExplorer
.\AddCodeToExplorerMenu.ps1 -AllUsers -RestartExplorer
.\AddCodeToExplorerMenu.ps1 -Revert -AllUsers -RestartExplorer
```

**Notes**

* If you right-click on **empty area** inside a folder and don’t see the item, ensure you added the **Background** target (this wrapper does).

---

### `AddCode_Verify.ps1`

**Description**
Checks all relevant registry locations under both **HKCU** and **HKLM** for the **Open\_with\_VS\_Code** entries and prints their Title/Icon/Command.

**Usage**

```powershell
.\AddCode_Verify.ps1
```

---

## Other Scripts

### `RestartExplorer.ps1`

**What it does:**
Stops `explorer.exe` (if running) and starts a new instance. Use when registry tweaks don’t reflect immediately.

### `IsAdmin.ps1`

**What it does:**
Returns whether the current PowerShell session is running as **Administrator**.

### `RunAsAdmin.ps1`

**What it does:**
Sample pattern for self-elevation: if not admin → relaunch the same script with arguments using `Start-Process -Verb RunAs` (UAC prompt), then exit the original. This is just a demonstration script.

---

## Template Engine (`ExpandTemplate.ps1`)

**Description**
Generates final files from templates (`.tmpl`) by expanding dynamic placeholders. This enables the user to create files (templates) with parameterized content, which depend on user-provided values (via script argument, in form of variables) or on environment variables.

Substitution of environment variables is convenient for dynamic insertion of OS-related stuff (such as current user name, home directory and other user-specific directories, content of the PATH environment variable), or values of user-defined environment variables within scripts and automated systems such as continuous integration/delivery.

Special-case: `.reg` (registry script files) outputs to the required **UTF-16 LE** encoding (all other outputs are **UTF-8**).

**Key features**

* **Placeholders**: `{{ ... }}` with a **namespace** and optional **pipe** filters.
  * General form: ``{{ Namespace.<Qualifier> < | Filter1 | Filter2 ... > }}``
  * Examples:
    * `{{ env.LOCALAPPDATA | pathappend:"Local\Programs\" | regesc }}`
    * `{{ env.USERNAME }}`
    * `{{ var.ScriptFile }}`
* **Namespaces**:
  * `var.<Name>` – user-provided variables (via `-Variables @{ ... }` or `-Variable Name Value`).
  * `env.<NAME>` – environment variables (e.g., `env.USERNAME`, `env.LOCALAPPDATA`).
  * *(Reserved for future)* `ps:` – evaluate PowerShell expressions (not implemented yet).
* **Filters** (chainable):
  * `regq` - escapes quotes (replaces `"` => `\"`); used e.g. for .reg (Windows Registry script) files
  * `regesc` - escapes quotes and backslashes (replaces `\` => `\\` and `"` => `\"`); used for .reg (Windows Registry script) files and others
  *  `pathappend:"\tail"` - appends paths with whatever follows the colon
  *  `pathquote` 
  *  `lower` - changes input string to lower case
  *  `upper` - changes input string to upper case
  *  `trim` - trims leading and trailing whitespace from the input string
  * `replace:"old":"new"` - 
  * `default:"fallback"` - 
  * `append:"text"` - appends literal text to the input string
  * `prepend:"text"` - prepends input string with literal text
* **Whitespace tolerant**: placeholders can span multiple lines; spaces/newlines around `|` are ignored.
* **Output path**:

  * `-Output` optional. If omitted, writes next to the template with `.tmpl` removed.

**Parameters**

* `-Template <path>` – template file (`.tmpl` recommended). Relative paths are resolved from the script’s location.
* `-Output <path>` – optional; if omitted, output = template without `.tmpl`.
* One of:

  * `-Variables @{ Name='value'; ... }` – hashtable of variables.
  * or multiple `-Variable Name -Value Value` pairs.

**Examples**

```powershell
# 1) Using env only (no variables)
.\ExpandTemplate.ps1 `
  -Template .\AddCode_Example1.reg.tmpl `
  -Output   .\AddCode_Example1.reg

# 2) Using a hashtable of variables
.\ExpandTemplate.ps1 `
  -Template .\AddCode_Example2.reg.tmpl `
  -Output   .\AddCode_Example2.reg `
  -Variables @{ Title = 'Open with VS Code' }

# 3) Multiple -Variable pairs
.\ExpandTemplate.ps1 `
  -Template .\My.reg.tmpl `
  -Variable Title -Value 'Open with VS Code' `
  -Variable Tool  -Value 'Code.exe'
```

**Placeholder Rules**

```text
{{ var.Title | regq }}
{{ env.USERPROFILE | pathappend:"\AppData\Local\Programs\Microsoft VS Code\Code.exe" | regq }}
```

* `var.Title` is replaced with the value of `Title`.
* `env.USERPROFILE` pulls from the environment.
* `pathappend` concatenates with correct slashes.
* `regq` quotes/escapes for .reg value strings.

**Examples & Helpers**

* `AddCode_GenerateRegScriptsFromTemplates.ps1` – example that expands:

  * `AddCode_Example_WithPlaceholders.reg` (a .reg with simple placeholders you can also fill manually),
  * `AddCode_Example1.reg.tmpl`,
  * `AddCode_Example2.reg.tmpl`.

> **Error handling:** if a `var.*` variable is referenced but not provided, or an environment variable is missing, the script prints a descriptive error and exits.

---

## Appendix – Quick Command Cheatsheet

```powershell
# Show classic full context menus
.\ShowFullContextMenus.ps1 -RestartExplorer
.\ShowFullContextMenus.ps1 -Revert -RestartExplorer

# Auto-hide taskbar (and revert)
.\HideTaskbar.ps1 -RestartExplorer
.\HideTaskbar.ps1 -Revert -RestartExplorer

# Desktop icons
.\SetDesktopIconSize.ps1                # Small
.\SetDesktopIconSize.ps1 -Revert        # Medium
.\SetDesktopIconSize.ps1 -Size Large -RestartExplorer

# Taskbar icons (Windows 11 may ignore)
.\SetTaskbarIconSize.ps1 -Size Small -RestartExplorer
.\SetTaskbarIconSize.ps1 -Revert -RestartExplorer

# Add “Open with VS Code”
.\AddCodeToExplorerMenu.ps1 -RestartExplorer
.\AddCodeToExplorerMenu.ps1 -AllUsers -RestartExplorer
.\AddCodeToExplorerMenu.ps1 -Revert -AllUsers -RestartExplorer

# GUI utility for sizes
.\IconSizeUtility.ps1
```

---

## Final Notes

* These tools intentionally **prefer clarity over minimal output** so you can see what’s happening. That’s invaluable when Windows behaviors differ across builds.
* If there is later a need reduce noise, we can gate the extra prints behind `-Verbose` or `-Debug`, or add a `-LogPath` to capture summaries to a file.
* If a consolidated installer/wrapper or Intune/GPO-friendly variants are needed, the functionality can also be extended to this.
