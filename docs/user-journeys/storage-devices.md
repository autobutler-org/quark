# Storage Devices Journeys

Covers the System page's Storage tab (`/system/storage`) — listing, mounting, renaming, and backing up storage devices connected to the quark.

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
2. Initiate a backup for a device.
3. Monitor the backup status.

**Expected result:**

- Backup job starts and a status indicator updates with progress.
- On completion, a success state is shown.
- Polling stops when the job is done.

---

### JN-SD-009: Vault storage location indicator

**Preconditions:** Vault is initialized and assigned to a specific device.

**Steps:**

1. Navigate to `/system/storage`.

**Expected result:**

- The device holding vault data is visually marked (icon or label).

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
- The drawer has no Vault entry for this account either (see JN-VT-000 in vault.md).
