# Notifications Journeys

Covers the notifications a Quark has for an account (`GET /api/v0/notifications`) and the setting that turns a
type off. The types today are the two backup reminders, `backup_due` and `backup_stale`.

**This is API-only today.** The app does not show notifications yet: the bell, the notification list and the
toggle for each type are a follow-up (part of #2493, under the epic #1145). The app shell already reserves
`QuarkAppBarTrailing` for the bell. Push delivery waits on #1150. Until the app catches up, the steps below are
requests a tester sends with a signed-in session.

---

### JN-NT-001: An admin is told a backup is due

**Preconditions:** User is signed in as an admin. This Quark has never completed a snapshot backup.

**Steps:**

1. Send `GET /api/v0/notifications`.

**Expected result:**

- `notifications` holds one entry with `type` `backup_due` and `link` `/system/storage`.
- The entry has no `lastBackupAt`.

**Notes:**

- A Quark whose last snapshot backup ran before this feature shipped also reads as due, because the completion
  time was not recorded then. Its next snapshot backup records it.
- Asking again returns the same single entry. Nothing is stored for each request, so the reminder cannot pile up.

---

### JN-NT-002: An admin is told the last backup is stale

**Preconditions:** User is signed in as an admin. The last snapshot backup completed 30 or more days ago.

**Steps:**

1. Send `GET /api/v0/notifications`.

**Expected result:**

- `notifications` holds one entry with `type` `backup_stale` and `link` `/system/storage`.
- `lastBackupAt` is when that backup completed.

**Notes:**

- The 30 days are `notificationutil.BackupStaleAfter`. The trigger policy is provisional until product settles it
  (#2493).
- A backup younger than 30 days produces no entry.

---

### JN-NT-003: The reminder clears after a snapshot backup

**Preconditions:** User is signed in as an admin and has a `backup_due` or `backup_stale` notification. A drive
with the snapshot-backup role is connected.

**Steps:**

1. Start a snapshot backup (JN-SD-008) and wait for it to complete.
2. Send `GET /api/v0/notifications`.

**Expected result:**

- `notifications` is an empty list.

**Notes:**

- A backup that fails or is canceled records nothing, so the reminder stays.
- The Quark publishes `backup_completed` on the event stream when the backup finishes; that is the client's cue
  to ask again.
- The completion time is kept on the Quark, not on the backup drive, so unplugging the drive afterwards does not
  bring the reminder back.

---

### JN-NT-004: Turn a notification type off

**Preconditions:** User is signed in as an admin and has a `backup_due` notification.

**Steps:**

1. Send `PUT /api/v0/settings/me` with `{"themeColor": "<current value>", "disabledNotifications": ["backup_due"]}`.
2. Send `GET /api/v0/notifications`.
3. Send `PUT /api/v0/settings/me` with `{"themeColor": "<current value>"}`.
4. Send `GET /api/v0/notifications`.

**Expected result:**

- After step 2, `notifications` is an empty list.
- After step 4, the `backup_due` entry is back.

**Notes:**

- The setting belongs to the account. Another admin still gets the reminder.
- `backup_due` and `backup_stale` are turned off separately.
- An unknown type, or the same type listed twice, is refused with 400 and nothing is saved.
- `PUT /settings/me` replaces the settings whole, which is why step 3 turns the type back on. The app's theme
  color write sends only `themeColor` today, so the follow-up that adds the toggle must make that write carry
  `disabledNotifications` too. Otherwise choosing a color turns every type back on.

---

### JN-NT-005: A non-admin gets no backup reminder

**Preconditions:** User is signed in as a non-admin. This Quark has never completed a snapshot backup.

**Steps:**

1. Send `GET /api/v0/notifications`.

**Expected result:**

- `notifications` is an empty list.

**Notes:**

- Only an admin can start a backup (JN-SD-010), so only admins are reminded.
