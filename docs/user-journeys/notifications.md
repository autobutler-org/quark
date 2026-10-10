# Notifications Journeys

Covers the notifications a Quark has for an account: the bell in every main page's top bar, the list it opens, and
the Settings switch that turns a type off. The types today are the two backup reminders, `backup_due` and
`backup_stale`.

The bell shows whenever someone is signed in. It wears a count while the account has notifications and no count
while it has none. Push delivery waits on #1150; this is in-app only (#2493, under the epic #1145).

---

### JN-NT-001: An admin is told a backup is due

**Preconditions:** User is signed in as an admin. This Quark has never completed a snapshot backup.

**Steps:**

1. Open any main page, such as Files.
2. Tap the bell in the top bar.
3. Tap **Back up this Quark**.

**Expected result:**

- After step 1, the bell shows a count of 1 and its tooltip reads "1 notification".
- After step 2, a **Notifications** sheet opens with one row, **Back up this Quark**, saying this Quark has never
  been backed up.
- After step 3, the sheet closes and the System page opens on its Storage tab, where a backup is started
  (JN-SD-008).

**Notes:**

- The list comes from `GET /api/v0/notifications`: one entry with `type` `backup_due`, `link` `/system/storage`
  and no `lastBackupAt`. The Quark sends no text; the app writes the row from the type.
- A Quark whose last snapshot backup ran before this feature shipped also reads as due, because the completion
  time was not recorded then. Its next snapshot backup records it.
- Opening the bell again shows the same single row. Nothing is stored for each request, so the reminder cannot
  pile up.
- Keys: `notifications_bell`, `notification_tile_backup_due`.

---

### JN-NT-002: An admin is told the last backup is stale

**Preconditions:** User is signed in as an admin. The last snapshot backup completed 30 or more days ago.

**Steps:**

1. Tap the bell in the top bar.

**Expected result:**

- The sheet has one row, **Your backup is out of date**, naming the date the last backup finished.
- Tapping the row opens the System page's Storage tab.

**Notes:**

- The entry's `type` is `backup_stale` and its `lastBackupAt` is when that backup completed.
- The 30 days are `notificationutil.BackupStaleAfter`. The trigger policy is provisional until product settles it
  (#2493).
- A backup younger than 30 days produces no row. A backup crosses the 30 days with no event, so the app asks
  again each time the bell is opened and each time the app comes back to the foreground.
- Key: `notification_tile_backup_stale`.

---

### JN-NT-003: The reminder clears after a snapshot backup

**Preconditions:** User is signed in as an admin and the bell shows a backup reminder. A drive with the
snapshot-backup role is connected.

**Steps:**

1. Start a snapshot backup (JN-SD-008) and wait for it to complete.
2. Tap the bell in the top bar.

**Expected result:**

- After step 1, the bell's count goes away without a reload.
- After step 2, the sheet says **You're all caught up**.

**Notes:**

- A backup that fails or is canceled records nothing, so the reminder stays.
- The Quark publishes `backup_completed` on the event stream when the backup finishes; that is the app's cue to
  ask again.
- The completion time is kept on the Quark, not on the backup drive, so unplugging the drive afterwards does not
  bring the reminder back.

---

### JN-NT-004: Turn a notification type off

**Preconditions:** User is signed in as an admin and the bell shows the **Back up this Quark** reminder.

**Steps:**

1. Open Settings. On the General tab, find **Notifications**.
2. Turn **No backup yet** off.
3. Tap the bell in the top bar, then close the sheet.
4. Pick a different theme color on the same tab.
5. Turn **No backup yet** back on.

**Expected result:**

- After step 1, there is one switch for each type, **No backup yet** and **Backup out of date**, both on.
- After step 2, the bell's count goes away.
- After step 3, the sheet says **You're all caught up**.
- After step 4, the switch is still off and the bell still has no count.
- After step 5, the bell's count is back.

**Notes:**

- The setting belongs to the account. Another admin still gets the reminder.
- `backup_due` and `backup_stale` are turned off separately.
- The switches are saved as `disabledNotifications` in `PUT /api/v0/settings/me`, next to `themeColor`. That
  request replaces the settings whole, so the app reads the settings and sends them all back with the one change.
  This is what step 4 checks: a color save that sent only `themeColor` would turn every type back on.
- An unknown type, or the same type listed twice, is refused with 400 and nothing is saved. If a save is refused,
  the switch flips back and the reason shows under the switches.
- Keys: `notification_toggle_backup_due`, `notification_toggle_backup_stale`.

---

### JN-NT-005: A non-admin gets no backup reminder

**Preconditions:** User is signed in as a non-admin. This Quark has never completed a snapshot backup.

**Steps:**

1. Tap the bell in the top bar.
2. Open Settings and look through the General tab.

**Expected result:**

- After step 1, the bell has no count and the sheet says **You're all caught up**.
- After step 2, there is no **Notifications** section.

**Notes:**

- Only an admin can start a backup (JN-SD-010), so only admins are reminded, and `GET /api/v0/notifications`
  answers a non-admin with an empty list.
- Both types today are backup reminders, so a non-admin has nothing to switch. The section will show for
  everyone once there is a type every account receives.
