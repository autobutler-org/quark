# Storage Devices Journeys

Covers the System page's Storage tab (`/system/storage`) — listing, mounting, renaming, assigning roles to, and backing up storage devices connected to the quark.

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

### JN-SD-008: Start a backup job

**Preconditions:** User is signed in as an admin. A storage device capable of backup is connected.

**Steps:**

1. Navigate to `/system/storage`.
2. Initiate a backup for a device (**Back Up**), then tap **Start Backup**.
3. Monitor the backup status.

**Expected result:**

- No password is asked. The dialog says chat and every account's vault are backed up still encrypted: on the drive
  when Quark keeps its own database, or in the operator's PostgreSQL backups on a PostgreSQL-backed install.
- Backup job starts and a status indicator updates with progress: "Preparing backup...", "Scanning files...", then
  "Copying files" with a percentage and file and byte counts.
- On completion, a success state is shown.
- Polling stops when the job is done.
- While your own backup runs, **Back Up** and **Verify** are disabled on the device cards.

**Notes:**

- A backup is a job on the Quark's job queue, so the Quark, not the page, owns it. Any instance of the Quark can
  answer the status poll, and reloading the page does not stop the backup.
- Only one backup per target drive runs at a time, whichever instance or admin started it. A second start onto the
  same drive is refused with a snack bar saying a backup is already running for it.
- A backup the Quark restarted in the middle of is queued again and runs from the start. Only one that was
  running through three crashes reads as **Backup failed**, with the snack bar "Backup failed: interrupted by
  restart". Start a new backup.
- If the status poll gets a 404, the job is gone for good: polling stops, the progress card clears and a snack bar
  says the backup couldn't be checked. Any other poll error keeps polling.
- Backups are not listed on the Jobs tab (JN-JOB-001), which shows video conversions only.

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
- No **Mount**, **Set Role**, **Back Up** or **Verify** button is offered on any device.

**Notes:**

- Every drive action is admin-only on the Quark (#1899). The page hides the buttons (#1928), and the Quark still
  refuses the requests.

---

### JN-SD-011: Set a device's role

**Preconditions:** User is signed in as an admin. Built-in storage and at least one mounted USB drive are listed.

**Steps:**

1. Navigate to `/system/storage`.
2. Tap **Set Role** on a device.
3. Choose **Default Storage**, **Snapshot Backup** or **Unassigned**.
4. Confirm your credentials.

**Expected result:**

- A snack bar names the new role and the device's badge changes. Only one device holds **Default Storage**: giving
  it to one takes it from the other.
- With more than one enabled device, the **Upload to device** sheet (JN-FB-006, JN-PH-006) and the one New folder
  opens start on the default storage device, and its row reads **Default**. The sheet is still shown, and any
  other enabled device can be chosen.
- **Set Role** on built-in storage offers **Default Storage** and **Unassigned** only, which is how built-in
  storage takes the role back from a USB drive.

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
3. Tap **Why two backup drives?**.
4. Dismiss the sheet, then tap **Why two backup drives?** again.
5. Dismiss the sheet and tap the card's next step.

**Expected result:**

- The card names the level the Quark reported: **Unprotected**, **Basic**, or **Protected**. The meter is filled
  through that level.
- The card shows the Quark's sentence. With no backup copy it reads "Your files are only on this Quark." With one
  good backup drive it names how many drives hold the files and says to add a second backup drive and keep it
  somewhere else. With two or more it says to keep one backup drive somewhere else.
- Each backup drive on the card shows when it was last backed up, or the reason the Quark sent when that drive
  does not count.
- The first snapshot-backup drive in the list carries a compact badge with the same level.
- The sheet is titled **Why two backup drives?** and shows what a fire, a theft, or a failed drive does to one
  copy versus three, plus the reminder to keep one backup drive somewhere else. Dismissing it closes it, and the
  card opens it again.
- **Assign the backup role** opens the Set Role dialog. **Start a backup** opens the backup dialog. **Keep one
  backup drive somewhere else** opens the same sheet.
- A non-admin sees the card, the badge, and the sheet, and does not see **Assign the backup role** or **Start a
  backup**.

**Notes:**

- The page shows the level the Quark sent. It does not count drives again. A stale backup, a failed backup, or a
  second partition of the same disk stays at the reason the Quark sent.
- Keeping a drive somewhere else is a sentence on the card, not a place the page stores.
- The page refresh reloads the card. The card also reloads when a backup finishes or fails.

---

### JN-SD-013: Read a drive's health before committing to it

<!-- cspell:words reallocated -->

**Preconditions:** User is logged in. At least one storage device is connected, and the Quark reports a health verdict for it.

**Steps:**

1. Navigate to `/system/storage`.
2. Read the health on a drive and the sentence under it.
3. Tap **Show details**.
4. As an admin, tap **Set Role** on a **Replace soon** drive, choose **Default Storage** or **Snapshot Backup**, and read the acknowledgment.
5. Confirm the acknowledgment, then confirm your credentials.
6. On a **Replace soon** backup drive, tap **Back Up** and read the acknowledgment before the backup starts.

**Expected result:**

- Every drive shows one verdict in words: **Healthy**, **Watch**, **Replace soon**, or **Unknown**, plus the one sentence the Quark sent.
- **Unknown** reads as Unknown. It does not read as Healthy. The sentence is the one the Quark sent, including when the health tool is not installed.
- **Show details** lists only the readings the Quark sent: SMART status, reallocated sectors, pending sectors, power-on hours, temperature, spinning or solid-state, link speed, and the speed class. A reading the Quark left out is not shown.
- Power-on hours are a count of hours. When the Quark calls the drive heavily used, the sentence says that. The page never states a manufacture year.
- Choosing default storage or the backup role, or starting a backup, on a **Replace soon** drive asks for an acknowledgment first. Confirming sends it. Canceling leaves the role and the backup unchanged. The acknowledgment says files already on the drive stay. Assigning the backup role or starting a backup also says the backup is added beside them.
- **Watch** does not ask for that acknowledgment. Switching default storage to a drive the Quark marked as worse than the current default storage shows the stronger warning. Continuing does not send an acknowledgment.
- A non-admin sees the verdict, the sentence, and the details, and is not offered **Set Role** or **Back Up**.

**Notes:**

- The page shows the verdict, the sentence, and whether the drive is worse than the current default storage, as the Quark sent them. It does not score the drive again.
- A future action that formats or erases a drive has to come through this same health check and acknowledgment. This journey does not erase a drive.
