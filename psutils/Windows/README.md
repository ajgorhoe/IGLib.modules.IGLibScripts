
# Windows Utility Scripts

[This directory](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/tree/main/psutils/Windows) of [IGLibScripts](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/) contains some useful Windows Utility scripts.

**Contents**:

* [Notes](#notes)

## Notes

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

See: [how to do it manually](https://learn.microsoft.com/en-gb/answers/questions/2006361/how-do-i-get-microsoft-code-to-come-up-in-my-right).

