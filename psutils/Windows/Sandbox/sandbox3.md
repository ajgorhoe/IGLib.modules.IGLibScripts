
# Windows - Ideas for Future Development

Some quick, ideas for further work, when convenient:

* **Safety net:** export the affected keys before changes (one-line `reg.exe export`) so `-Revert` can optionally restore from a backup file.
* **Logging:** add `-LogPath` to append a timestamped summary (what hives/targets were added/removed) for auditability.
* **Scope control:** if granular control on revert is needed, add a `-Scope CurrentUser|AllUsers|Both` switch (right now `-AllUsers -Revert` removes HKLM + HKCU, which seems perfect for my typical use cases).
* **GPO flavor:** a companion `.reg` pair (HKLM only) makes it easy to deploy via GPO or Intune; I already have the patterns from earlier.
* **Code signing:** if I run these scripts in stricter environments,I would need to add a signed version and `#requires -RunAsAdministrator` to make intent explicit.

For now, the functionality is sufficient without these additions, but if any of this is needed, it can be implemented.
