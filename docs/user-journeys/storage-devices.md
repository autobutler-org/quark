# Storage Devices Journeys

Covers the System page's Storage tab (`/system/storage`) — listing, mounting, renaming, assigning roles to, backing up onto, listing and deleting the backups on, and restoring files from storage devices connected to the quark.

---

### JN-SD-001: View connected storage devices

**Preconditions:** User is logged in. At least one storage device is connected to the quark.

**Steps:**

1. Navigate to `/system/storage`.

**Expected result:**

- List of storage devices is displayed.
- Each device shows: name, serial, mount status, and storage usage bar.

**Notes:**

- The **Storage** tab of the System page, which **System** in the drawer opens. The old `/devices` address
  redirects here.

---

### JN-SD-002: View storage devices page with no devices

**Preconditions:** No storage devices are connected to the quark.

**Steps:**

1. Navigate to `/system/storage`.

**Expected result:**

- Empty state or informational message is shown (not a crash).

---

### JN-SD-003: Mount an unmounted device

**Preconditions:** User is signed in as an admin. A storage device is connected but not yet mounted.

**Steps:**

1. Navigate to `/system/storage`.
2. Find the unmounted device in the list.
3. Tap **Mount**.

**Expected result:**

- Device status changes to mounted.
- A success snackbar or confirmation is shown.
- Files on the device become accessible in the file browser.

---

### JN-SD-004: Auto-refresh device list

**Preconditions:** User is on `/system/storage`.

**Steps:**

1. Wait for the auto-refresh interval to elapse.

**Expected result:**

- Device list refreshes without manual intervention.
- Status changes (e.g. a newly connected device) are reflected.

---

### JN-SD-005: Manually refresh device list

**Preconditions:** User is on `/system/storage`.

**Steps:**

1. Tap the **Refresh** button.

**Expected result:**

- Device list reloads immediately.

---

### JN-SD-006: Rename a storage device

**Preconditions:** User is signed in as an admin. At least one storage device is listed.

**Steps:**

1. Navigate to `/system/storage`.
2. Tap the rename action on a device (or long-press for context menu).
3. Enter a new name.
4. Confirm.

**Expected result:**

- Device appears in the list with the new name.

---

### JN-SD-007: View storage usage bar

**Preconditions:** At least one mounted storage device is connected.

**Steps:**

1. Navigate to `/system/storage`.

**Expected result:**

- Each device shows a visual storage usage bar indicating used vs. total capacity.
- Used and total sizes are shown as human-readable values (GB, TB).

---

### JN-SD-008: Back up onto a backup drive

**Preconditions:** User is signed in as an admin. A drive with the **Backup drive** role is connected, and at least
one other drive holds files.

**Steps:**

1. Navigate to `/system/storage`.
2. Tap **Back up onto this drive** on the backup drive's card.
3. Read the dialog, uncheck any data drive to leave out, then tap **Start Backup**.
4. Watch the backup drive's card until the backup finishes.

**Expected result:**

- The dialog is titled **Back up onto this drive**, says "Choose the drives to copy onto Backup A.", and lists a
  checkbox for each data drive, every attached drive that is not a backup drive. Another backup drive is never
  listed, and never copied. Every drive starts checked, and **Start Backup** is off while none is.
- With every drive checked the backup copies every data drive, as **Back up now** does (JN-SD-012). With one
  unchecked it copies only the checked drives, and the progress names only those.
- No password is asked. The dialog says chat and every account's vault are backed up still encrypted: on the drive
  when Quark keeps its own database, or in the operator's PostgreSQL backups on a PostgreSQL-backed install.
- The progress shows on the backup drive's card and names the drives: "Preparing to back up onto Backup A",
  "Scanning Built-in storage, Photos", then "Copying Built-in storage onto Backup A · 42%" with file and byte
  counts. The drive it names changes as each data drive is copied.
- On completion a snack bar says the backup completed, and the progress goes. The card then reads what the drive
  holds, such as "Holds copies of Built-in storage, Photos. Newest Nov 8.", its backups list gains the new one
  (JN-SD-016), and each data drive's chip shows the new copy (JN-SD-012).
- On failure a snack bar says the backup failed and why, and the progress goes. What the drive held before stays on
  its card.
- While any backup runs, **Back up onto this drive**, **Verify**, **Restore vaults**, **Restore files** and **Eject**
  are disabled on every drive card. That holds for a backup started in another tab, on another device, or by another
  admin: the page finds it in the device list, shows its progress, and follows it to the end.

**Notes:**

- A backup is a job on the Quark's job queue, so the Quark, not the page, owns it. Any instance of the Quark can
  answer the status poll, and reloading the page does not stop the backup.
- Only one backup per target drive runs at a time, whichever instance or admin started it. A second start onto the
  same drive is refused with a snack bar saying a backup is already running for it.
- **Back up now** on the protection card (JN-SD-012) starts the same backup onto every connected backup drive that is
  not already receiving one and is not **Replace soon**, without the dialog. A Replace soon drive is backed up from
  its own card, which asks for the acknowledgment first (JN-SD-013).
- Each backup is a new folder, `backups/<date> <time>/` on the backup drive, such as `backups/2026-11-08 07.10/`,
  holding one folder per data drive (`Built-in storage`, `Photos (USB 90C82C65)`). Files unchanged since the last
  backup are shared with it rather than copied again, except on a FAT or exFAT drive, which gets a full copy every
  time. A backup that does not finish leaves no folder behind.
- The drive chips and the backup drive's card read what the backup folders on the drive hold. When the backup drive
  is unplugged, they read what the Quark found the last time it was attached.
- A backup onto a drive short of space deletes its oldest backups first (JN-SD-018).
- A backup the Quark restarted in the middle of is queued again and runs from the start. Only one that was
  running through three crashes reads as **Backup failed**, with the snack bar "Backup failed: interrupted by
  restart". Start a new backup.
- If the status poll gets a 404, the job is gone for good: polling stops, the progress card clears and a snack bar
  says the backup couldn't be checked. Any other poll error keeps polling.
- **Verify** checks the newest backup on the drive and names it: "Verified the backup of Nov 8, 07.10: 1204 files
  OK.", or how many files are missing or corrupted. On a backup drive that has never been backed up onto it says
  there is nothing to verify yet: back up onto this drive first.
- Backups taken before the dated folders, which sit at the drive's root, are not verified or restored. Take a new
  backup after upgrading; the old root folders can then be deleted by hand.
- The backup is also listed on the Jobs tab (JN-JOB-001), with Cancel and Retry. Its name says which drives it copies
  and onto which drive, such as **Back up Quark, Photos onto Built-in storage**; past two drives it counts the rest
  ("and 2 more").

---

### JN-SD-009: Vault storage location indicator (retired)

Retired by #3456: each account's vault lives in the main database, not on a drive, so no device is marked as
holding it.

---

### JN-SD-010: A non-admin sees drives without drive actions

**Preconditions:** User is signed in to an account that is not an admin. At least one storage device is connected,
including one that is not mounted.

**Steps:**

1. Navigate to `/system/storage`.

**Expected result:**

- The device list, usage bars and badges are shown as they are for an admin.
- No **Mount**, **Set Role**, **Back up onto this drive**, **Verify** or **Restore files** button is offered on any
  device, a backup drive's card has no backups list (JN-SD-016), and the protection card offers no **Back up now**.

**Notes:**

- Every drive action is admin-only on the Quark (#1899). The page hides the buttons (#1928), and the Quark still
  refuses the requests.

---

### JN-SD-011: Set a device's role

**Preconditions:** User is signed in as an admin. Built-in storage and at least one mounted USB drive are listed.

**Steps:**

1. Navigate to `/system/storage`.
2. Tap **Set Role** on a device.
3. Choose **Default Storage**, **Backup drive** or **Unassigned**.
4. Confirm your credentials.

**Expected result:**

- A snack bar names the new role and the device's badge changes. Only one device holds **Default Storage**: giving
  it to one takes it from the other.
- With more than one enabled device, the **Upload to device** sheet (JN-FB-006, JN-PH-006) and the one New folder
  opens start on the default storage device, and its row reads **Default**. The sheet is still shown, and any
  other enabled device can be chosen.
- On a USB drive, **Backup drive** reads "Your other drives are copied onto it when you back up. Keep it somewhere
  safe between backups." The badge on its card reads **Backup drive**.
- **Set Role** on built-in storage offers **Default Storage**, **Backup drive**, and **Unassigned**.
  **Backup drive** makes built-in storage the drive other drives are copied onto. That backup does not copy
  built-in storage onto itself, and a copy on built-in storage protects the other drives and never built-in
  storage's own files. **Default Storage** and **Unassigned** are how built-in storage takes the default role back
  from a USB drive.
- A drive that becomes a backup drive stops being a data drive: its chip goes, and it is not copied onto the other
  backup drives. A drive that stops being a backup drive becomes a data drive, starts at **Not backed up**, and is
  copied by the next backup.

**Notes:**

- With no device holding the role, built-in storage is where a request naming no device lands, but no row reads
  **Default** and the sheet starts on the device chosen last time, then on the first one listed.
- When the default storage drive is not enabled it is listed as unavailable, still reading **Default**, and the
  sheet starts on the fallback above. When it is unplugged it is not listed at all and nothing says it is missing.
- A view filtered to one device still uploads to that device without asking (JN-FB-006).
- A USB drive holding **Default Storage** is also what live sync copies built-in storage onto. Files uploaded
  straight to that drive are not copied back, and get no version history.
- The role is the upload sheet's starting point only: a request that names no device still writes to built-in
  storage.

---

### JN-SD-012: Read how protected the files are

**Preconditions:** User is logged in. The Quark answers the protection status for the files.

**Steps:**

1. Navigate to `/system/storage`.
2. Read the protection card at the top of the drive list.
3. Read the chip on each data drive's card, then tap one that has copies.
4. Read a backup drive's card.
5. Tap **Why two backup drives?**, dismiss the sheet, and tap it again.
6. Dismiss the sheet. As an admin, tap the card's next step or **Back up now**.

**Expected result:**

- Each data drive (built-in storage, the main storage drive, and any other drive that is not a backup drive) carries
  a chip with its own state: **Not backed up**, **Backed up Nov 2 · Backup A** with one counting copy, or
  **Protected · Nov 2** with counting copies on two different disks. Tapping a chip that has copies opens one line
  per backup drive, such as "Backup A · Nov 2", followed by the Quark's reason when that copy does not count: it is
  more than 30 days old, it is on the same disk as the drive, it is on the same disk as another copy, or the drive
  holding it should be replaced soon.
- A backup drive carries no protection badge or chip. Its card says what it holds, "Holds copies of Built-in
  storage, Photos. Newest Nov 2.", or "No copies yet." A drive that is missing a data drive, or whose copies are
  more than 30 days old, adds "Back up onto this drive to bring it up to date." A **Replace soon** backup drive adds
  "Replace this drive soon. Its copies no longer count."
- The protection card names the whole Quark's level, which is its weakest data drive's: **Unprotected** when any
  data drive has no counting copy, **Basic** when every one has at least one, and **Protected** when every one has
  two on different disks. The meter is filled through that level.
- The card shows the Quark's sentence, written from the weakest data drive: "Built-in storage is only on this
  Quark." or "Photos has no recent backup." followed by what to do, "Every drive has a copy on one backup drive.",
  or "Every drive is on two backup drives. Keep one somewhere else."
- For an admin the card has **Back up now** while a connected backup drive can take a backup. It starts a backup
  onto every connected backup drive that is not already receiving one and is not Replace soon (JN-SD-008), and the
  progress shows on each of their cards.
- **Assign the backup role** opens the Set Role dialog on a drive that is neither a backup drive nor the main storage
  drive. When no such drive is attached, the step is not offered. **Keep one backup drive somewhere else** opens the
  sheet.
- The sheet is titled **Why two backup drives?** and shows what a fire, a theft, or a failed drive does to one
  copy versus three, plus the reminder to keep one backup drive somewhere else. Dismissing it closes it, and the
  card opens it again.
- A non-admin sees the card, the chips, the backup drives' text, and the sheet, and does not see **Assign the backup
  role** or **Back up now**.

**Notes:**

- The page shows the levels and reasons the Quark sent. It does not count copies again. A copy counts only when it
  is inside 30 days, its backup drive is not Replace soon, and the backup drive is on a different physical disk from
  the data drive. Two partitions of one backup disk count once for a drive.
- A backup drive that is unplugged keeps its copies on record, so the data drives it backed up keep their chips.
- The live copy that sync keeps on a USB main storage drive is a mirror, not a backup copy, and does not count.
- Copies are read from the backup folders on each backup drive. Deleting a backup (JN-SD-017) or a backup pruning
  old ones (JN-SD-018) can move a chip back to **Not backed up** or **Backed up**. Backups in the old layout at a
  drive's root do not count, so a Quark last backed up before the dated folders reads **Not backed up** until its
  next backup.
- Keeping a drive somewhere else is a sentence on the card, not a place the page stores.
- The page refresh reloads the card and the chips. They also reload when a backup finishes or fails.

---

### JN-SD-013: Read a drive's health before committing to it

<!-- cspell:words reallocated -->

**Preconditions:** User is logged in. At least one storage device is connected, and the Quark reports a health verdict for it.

**Steps:**

1. Navigate to `/system/storage`.
2. Read the health on a drive and the sentence under it.
3. Tap **Show details**.
4. As an admin, tap **Set Role** on a **Replace soon** drive, choose **Default Storage** or **Backup drive**, and read the acknowledgment.
5. Confirm the acknowledgment, then confirm your credentials.
6. On a **Replace soon** backup drive, tap **Back up onto this drive** and read the acknowledgment before the backup starts.

**Expected result:**

- Every drive shows one verdict in words: **Healthy**, **Watch**, **Replace soon**, or **Unknown**, plus the one sentence the Quark sent.
- **Unknown** reads as Unknown. It does not read as Healthy. The sentence is the one the Quark sent, including when the health tool is not installed.
- **Show details** lists only the readings the Quark sent: SMART status, reallocated sectors, pending sectors, power-on hours, temperature, spinning or solid-state, link speed, and the speed class. A reading the Quark left out is not shown.
- Power-on hours are a count of hours. When the Quark calls the drive heavily used, the sentence says that. The page never states a manufacture year.
- Choosing default storage or the backup role, or starting a backup, on a **Replace soon** drive asks for an acknowledgment first. Confirming sends it. Canceling leaves the role and the backup unchanged. The acknowledgment says files already on the drive stay. Assigning the backup role or starting a backup also says the backup is added beside them.
- **Watch** does not ask for that acknowledgment. Switching default storage to a drive the Quark marked as worse than the current default storage shows the stronger warning. Continuing does not send an acknowledgment.
- A non-admin sees the verdict, the sentence, and the details, and is not offered **Set Role** or **Back up onto this drive**.

**Notes:**

- The page shows the verdict, the sentence, and whether the drive is worse than the current default storage, as the Quark sent them. It does not score the drive again.
- A future action that formats or erases a drive has to come through this same health check and acknowledgment. This journey does not erase a drive.

---

### JN-SD-014: Eject a plugged-in drive

**Preconditions:** User is signed in as an admin. A USB storage drive is connected and mounted.

**Steps:**

1. Navigate to `/system/storage`.
2. Tap **Eject** on the drive.
3. Read the confirmation, then tap **Eject**.

**Expected result:**

- The confirmation says Quark stops using the drive and its files leave Files until it is mounted again. On the default storage drive it also warns that new uploads will fail until then.
- Canceling leaves the drive mounted.
- After **Eject**, a message says the drive is safe to unplug, and its card reads **Not mounted · safe to unplug** with a **Mount** button.
- **Eject** is disabled while a backup runs. When the drive's files are still in use, the Quark refuses and the page shows the error.
- A non-admin is not offered **Eject**.

---

### JN-SD-015: Restore files from a snapshot drive

**Preconditions:** User is signed in as an admin. A drive with the **Backup drive** role is connected and holds a snapshot. The drives those files came from are attached.

**Steps:**

1. Navigate to `/system/storage`.
2. Tap **Restore files** on the backup drive.
3. Read which backup the dialog names. On a drive with more than one, pick another from the **Backup** menu.
4. Read the confirmation, then tap **Restore**.

**Expected result:**

- The dialog is titled **Restore files from this drive**. It says each drive's files go back onto that drive, and that a file already there is kept as it is. It also says a snapshot keeps files that were deleted since, so the restore brings them back.
- The dialog names the backup it reads, "From the backup of Nov 2, 09.00.", which is the newest on the drive until another is picked. The menu lists every backup on the drive by its time and size.
- Canceling restores nothing.
- After **Restore**, a snack bar says how many drives' files are being restored and from which backup, "Restoring files from 2 drives, backed up Nov 2, 09.00.". Each drive's files come back onto that drive. Files already there are kept, and files deleted since the snapshot return.
- The copy runs as a job named after the snapshot drive, such as **Restore files from Backup**. The Jobs tab follows
  it.

**Notes:**

- **Restore files** is offered only on a drive with the **Backup drive** role, and only to an admin (JN-SD-010). It is disabled while any backup runs, including one started elsewhere.
- When a drive the files came from is not attached, tick **Put the files of a drive that is not attached on built-in storage**, then tap **Restore**. Those files land in a folder named after the snapshot folder on built-in storage, and the snack bar names that folder as going to built-in storage.
- With that box left clear, those files stay on the backup drive. The snack bar names the folder and says its drive is not attached. When every drive in the snapshot is gone, the Quark refuses and says to restore them to built-in storage instead.
- On a backup drive that holds no backup yet, the restore says there are no backups on this drive yet and to back up onto it first.
- While the restore runs, the backup it reads cannot be deleted (JN-SD-017) and is never pruned (JN-SD-018).
- Backups taken before the dated folders, which sit at the drive's root, are not offered.

---

### JN-SD-016: List the backups on a backup drive

**Preconditions:** User is signed in as an admin. A drive with the **Backup drive** role is connected and mounted, and
at least one backup onto it has completed (JN-SD-008).

**Steps:**

1. Navigate to `/system/storage`.
2. Read the backups line on the backup drive's card.
3. Tap it to open the list, then tap it again.

**Expected result:**

- The line sums up the drive's backups, "2 backups · newest Nov 2", or reads "No backups yet" on a drive that has
  none. The list starts closed.
- Opened, it shows one row per backup, newest first: its time, such as "Nov 2, 09.00", then its size and the drives
  it holds, "1.2 GB · Built-in storage, Photos". Each row has a **Delete backup** action (JN-SD-017).
- Tapping the line again closes the list.
- When the backups can't be listed, the card says so in place of the rows; the rest of the card still shows.

**Notes:**

- Each backup is a folder under `backups/` on the drive, named after the time it started in the Quark's local time,
  such as `2026-11-02 09.00`. A second backup started in the same minute reads "Nov 2, 09.00 (2)".
- A backup still being written is not listed, and neither are backups in the old layout at the drive's root.
- A backup's size counts every file it holds, including the files it shares with other backups, so the sizes can add
  up to more than the drive holds.
- The list reloads when a backup completes or a backup is deleted, here or elsewhere, and on the page's refresh.
- A non-admin's card has no backups line (JN-SD-010). The Quark refuses the listing to a non-admin too.
- Rows are keyed `backup_runs_<drive>` (the line), `backup_run_<drive>_<index>`, and
  `backup_run_delete_<drive>_<index>`.

---

### JN-SD-017: Delete a backup from a backup drive

**Preconditions:** User is signed in as an admin. A connected backup drive holds at least one backup, and no backup
onto it is running.

**Steps:**

1. Navigate to `/system/storage` and open the backup drive's backups list (JN-SD-016).
2. Tap **Delete backup** on a row.
3. Read the confirmation, then tap **Delete**.

**Expected result:**

- The confirmation is titled **Delete this backup?**. It says the backup of that time is deleted for good and can't
  be undone, and that deleting it may free less space than its size, because backups share the files that did not
  change between them.
- **Cancel** deletes nothing.
- After **Delete**, a snack bar says "Deleted the backup of Nov 2, 09.00.", the row goes, and the protection card,
  the backup drive's card and the data drives' chips reload. A data drive whose only fresh copy was in that backup
  moves back a level (JN-SD-012).
- Every other backup on the drive stays whole and can still be verified and restored.

**Notes:**

- The backup's folder is deleted from the drive for good. It does not go to the trash.
- While a backup onto that drive is running, or a restore is reading that backup, the Quark refuses and the snack bar
  says a backup or restore is using this drive and to try again once it finishes. Nothing is deleted.
- Other open pages see the delete: their lists and protection status reload.
- Any backup can be deleted, the newest included. Only the automatic pruning keeps the newest (JN-SD-018).

---

### JN-SD-018: A backup makes room by pruning old backups

**Preconditions:** User is signed in as an admin. A connected backup drive holds two or more backups and has less
free space than the next backup needs to copy.

**Steps:**

1. Navigate to `/system/storage`.
2. Tap **Back up onto this drive** on the backup drive, then **Start Backup** (JN-SD-008).
3. Watch the card until the backup finishes, then open its backups list (JN-SD-016).

**Expected result:**

- Before copying, the backup deletes the drive's oldest backups, one at a time, until the drive has room. It
  then copies and completes as in JN-SD-008.
- The list no longer shows the deleted backups and shows the new one. The newest backup from before is still there.
- When the drive has too little room even with every backup but the newest deleted, the backup fails before copying
  anything, and the snack bar says "Not enough space on Backup A for this backup: delete old backups or use a bigger
  drive." The newest backup from before is still there.

**Notes:**

- The room needed is what the backup will copy, not the size of the drives: on a drive that shares unchanged files
  between backups, only the new and changed files count. A FAT or exFAT drive shares nothing, so every backup needs
  room for a full copy.
- Free space is read again after each delete, because a backup sharing files with others frees less than its size.
- The newest backup is never pruned, nor a backup a restore is reading. Backups pruned before a failure stay
  deleted.
- A drive whose free space the Quark cannot read is not pruned.
- Pruning is not shown while it happens. Each pruned backup is announced like a delete, so open pages reload their
  lists and protection status.
