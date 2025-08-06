
# Windows Utility Scripts

[This directory](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/tree/main/psutils/Windows) of [IGLibScripts](https://github.com/ajgorhoe/IGLib.modules.IGLibScripts/) contains some useful Windows Utility scripts.

## Notes

Disabling Modern Standby (S0 mode) and enabling the Standard Sleep (S3 mode) would not work on many modern laptops (because many OEMs are disabling the S3 mode in firmware) and because of this, a PowerShell script to do this was not provided. Only the registry edit scripts were provided, the `EnableS3Standby_NormalSleep.reg` for enabling the normal sleep mode, and `DisableS0Standby_ModernStandby.reg` to disable the Modern Standby (which, if it works, may result in crashing computer when sleep mode is entered via UI or buttons / closing the lid of a laptop). Some links are in the first registry file. See also:

* 
* [Getting back S3 sleep and disabling modern standby under Windows 10 >=2004](https://www.reddit.com/r/Dell/comments/h0r56s/getting_back_s3_sleep_and_disabling_modern/?utm_source=chatgpt.com) (Reddit)
* [Disable Modern Standby in Windows 10 and Windows 11 ](https://www.elevenforum.com/t/disable-modern-standby-in-windows-10-and-windows-11.3929/?utm_source=chatgpt.com) (ElevenForum)
* Some **General Resources for Windows Admin & Hacks**:
* [Windows 11 Tutorials (Winareo)](https://winaero.com/windows-11-tutorials/) - many useful Registry settings and other Windows hacks
* [ElevenForum List of Topics](https://www.elevenforum.com/) (topics, tutorials and hacks for Windows 11 and other computer-related)
  * E.g. useful for Win not updating any more:
    * [Win 11 updates Tutorials](https://www.elevenforum.com/tutorials/?prefix_id=17)
        * [Windows 11 Updates ?? ](https://www.elevenforum.com/t/windows-11-updates.29640/)

