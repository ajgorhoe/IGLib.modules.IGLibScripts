
### Remark - Applying Registry Changes for All Users

Under the hood there are **two different “All users” models** in the scripts, depending on what Windows actually reads for that feature.

---

#### 1) Per-machine registration (no per-user iteration)

**Script:** `AddContextMenuItem.ps1`
**Switch:** `-AllUsers`

* **What it does:** Writes to **HKLM\Software\Classes** (machine-wide “Classes” hive).
* **Why this works for all users:** Explorer resolves shell verbs and associations by looking at `HKCU\Software\Classes` first and then **falls back to** `HKLM\Software\Classes`. So placing the verb under HKLM makes it visible to **every profile** without touching each user hive.
* **Result:** One write to HKLM; no SID/user loop needed.
* **Elevation:** Required (writing under HKLM).

> Example destination keys (no iteration):
>
> * `HKLM\Software\Classes\*\shell\<KeyName>\command`
> * `HKLM\Software\Classes\Directory\shell\<KeyName>\command`
> * `HKLM\Software\Classes\Directory\Background\shell\<KeyName>\command`

---

#### 2) Per-user preference replication (iterate SIDs / hives)

**Script:** `RemoveTaskbar.ps1` (and similar HKCU-based tweaks)
**Switch:** `-AllUsers`

* **What it does:** The setting lives in **each user’s HKCU** (e.g., `HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3` or `...\Advanced`). To “apply for all users”, the script must **replicate** the HKCU change into **every user hive**.
* **How targets are chosen:**

  1. **Enumerate user profiles / SIDs**:

     * Read `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList` to get profile SIDs and `ProfileImagePath` (e.g., `C:\Users\Alice`).
     * Or enumerate **loaded hives** under `HKEY_USERS` and filter valid SIDs.
  2. **Skip non-interactive accounts**:

     * Well-known service/system SIDs are ignored:
       `S-1-5-18` (LocalSystem), `S-1-5-19` (LocalService), `S-1-5-20` (NetworkService), and service SIDs like `S-1-5-80-...`.
  3. **Current user**:

     * Apply via **HKCU** (simplest and always writable in the current session).
  4. **Other users**:

     * If their hive is **already loaded** (appears as `HKEY_USERS\<SID>`), write directly to
       `Registry::HKEY_USERS\<SID>\Software\Microsoft\Windows\CurrentVersion\Explorer\...`.
     * If the hive is **not loaded** (user logged off), you *can* attempt a **temporary load**:

       * `reg.exe load HKU\TempHive_<SID> "<ProfileImagePath>\NTUSER.DAT"`
       * Write your values under `HKU\TempHive_<SID>\...`
       * `reg.exe unload HKU\TempHive_<SID>`
       * ⚠️ This **fails** if the profile is in use (file locked) or if permissions prevent loading.
* **Decision to apply or skip per SID** is therefore based on:

  * Is it a **real profile SID**? (from ProfileList)
  * Is it **not** a service/system SID?
  * Is the hive **available** (loaded) or can it be **safely loaded**?
  * Does the **target key exist** (some profiles may not have created the Explorer key yet); if missing, the script can create the path or skip with a warning.
* **Elevation:** Required (to enumerate ProfileList, load hives, and write under HKEY\_USERS for other identities).

> Typical flow (simplified):
>
> ~~~powershell
> $profiles = Get-ProfileSidsAndPaths
> foreach ($p in $profiles) {
>   if ($p.Sid -eq $CurrentSid) { Write-HKCU; continue }
>   if (IsServiceSid($p.Sid))   { continue }
>   if (Test-Path "Registry::HKEY_USERS\$($p.Sid)") {
>       # Hive is loaded – write directly
>       Write-HKU $p.Sid
>   } else {
>       # Optional: load if offline & safe
>       if (Try-LoadHive $p) { Write-HKU TempHive_$($p.Sid); Unload-Hive }
>       else { Warn "Hive not loaded / in use – skipped" }
>   }
> }
> ~~~

---

#### Why behavior differs between your two scripts

* `AddContextMenuItem.ps1` **doesn’t need** to touch users at all for `-AllUsers`; it leverages HKLM so Explorer sees it for everyone.
* `RemoveTaskbar.ps1` is changing a **per-user preference**, so it either:

  * updates **only** the current user if you run without `-AllUsers`, or
  * tries to **replicate** to others by iterating SIDs/hives when you use `-AllUsers`, with the practical limitations above (locked hives, service SIDs, etc.).

---

#### Practical notes & limitations

* Some per-user changes only **take effect on next logon** or after **Explorer restart**. Your scripts print that guidance and optionally restart Explorer.
* Loading another user’s hive is **best-effort**: it works when the user is **logged off** and you have permissions; otherwise you’ll see “file in use” or similar and the script should warn and move on.
* Even when registry writes succeed for other users, they won’t see the effect until their **next logon** (or until their Explorer reads the value again).

