# Vault Journeys

Covers the Vault (`/vault`) — password manager setup, entry management, folders, import/export.

Every account has a vault of its own (#3456), and every journey here works the same for a member and an admin. The
vault is encrypted and decrypted in the app with a key that opens with the account's login password, so there is no
second password, and the Quark stores only ciphertext. Nobody else can open an account's vault, an admin included,
and there is no admin recovery: losing both the password and the recovery phrase loses the vault.

---

### JN-VT-000: A member has their own vault

**Preconditions:** Two accounts, an admin and a member who is not an admin. Each has set up a vault (JN-VT-001) and
saved an entry in it (JN-VT-006).

**Steps:**

1. Signed in as the member, open the navigation drawer and tap **Vault**.
2. Unlock the vault with the member's password (JN-VT-003).
3. Sign out, sign in as the admin, and open `/vault`.

**Expected result:**

- The drawer has a **Vault** row for the member, and `/vault` opens for them.
- The member sees only their own entries, and the admin only theirs. Neither vault shows the other's.

**Notes:**

- The vault page asks the Quark for the signed-in account's own vault only. Another account's item id reads as not
  found, for an admin too.
- A change saved in one session reaches the same account's other open sessions, which read the vault again. No
  other account hears of it.

---

### JN-VT-001: Set up the vault for the first time

**Preconditions:** The signed-in account has no vault yet.

**Steps:**

1. Navigate to `/vault`.
2. The app shows **Set up your vault** (not the unlock form or the entry list).
3. Enter the password you sign in to Quark with.
4. Optionally, enter the account's recovery phrase in **Recovery phrase (optional)**.
5. Tap **Set up vault**.

**Expected result:**

- The vault opens on the empty entry list.
- A password that is not the account's login password shows "That isn't your account password. The vault opens with
  the password you sign in with." and sets nothing up.

**Notes:**

- The app makes a random vault key and stores it on the Quark wrapped under a key the password derives. The
  password itself is never sent. The same derivation gives the password's auth key, which the Quark checks before
  it stores anything, so the vault is always wrapped under the login password and a later password change
  (JN-VT-020) keeps it.
- With the recovery phrase filled in, the key is also stored wrapped under a key the phrase derives, so a recovery
  with that phrase keeps the vault (JN-VT-020). Nothing checks the phrase against the Quark: a mistyped one is
  accepted and simply never opens the vault.
- A vault set up without the phrase has no phrase wrap. It gets one only when the account is next given a new
  recovery phrase, and until then a recovery cannot keep it.

---

### JN-VT-002: Vault requires device — no device connected (retired)

Retired by #3456: the vault lives in the main database, not on a storage device, so it never waits for a drive.

---

### JN-VT-003: Unlock the vault

**Preconditions:** The account has a vault (JN-VT-001), and it is locked.

**Steps:**

1. Navigate to `/vault`.
2. The app shows **Your vault is locked**.
3. Enter the password you sign in to Quark with.
4. Tap **Unlock**.

**Expected result:**

- The vault unlocks and the entry list is displayed.
- Folders and entries are visible.

**Notes:**

- The vault stays unlocked across pages until it is locked (JN-VT-005), sits untouched for 15 minutes, or the
  account signs out.

---

### JN-VT-004: Unlock with wrong password

**Preconditions:** The account has a vault, and it is locked.

**Steps:**

1. Navigate to `/vault`.
2. Enter a password other than the login password.
3. Tap **Unlock**.

**Expected result:**

- "That password doesn't unlock your vault." appears under the field.
- The vault stays locked.

**Notes:**

- The password is checked in the app, against the wrapped key, so a wrong one sends nothing to the Quark.

---

### JN-VT-005: Lock the vault

**Preconditions:** The vault is unlocked.

**Steps:**

1. Navigate to `/vault`.
2. Tap **Lock vault** in the top bar.

**Expected result:**

- The vault goes back to **Your vault is locked**.
- The entry list is no longer visible.

**Notes:**

- Locking forgets the key and every decrypted entry on this device. Fifteen minutes without use does the same.

---

### JN-VT-006: Add a new vault entry

**Preconditions:** The vault is unlocked.

**Steps:**

1. Navigate to `/vault`.
2. Tap **New entry** in the top bar.
3. Fill in: name, website, username, password, notes (at minimum the name).
4. Tap **Save**.

**Expected result:**

- The new entry appears in the entry list.
- Entry details match what was entered.

---

### JN-VT-007: View an existing vault entry

**Preconditions:** The vault is unlocked and has at least one entry (JN-VT-006).

**Steps:**

1. Tap an entry in the list.

**Expected result:**

- The entry's details open, showing its fields.
- The password is masked until revealed.
- Username, password and website each have a copy button, which copies the value to the clipboard.

---

### JN-VT-008: Edit a vault entry

**Preconditions:** The vault is unlocked and has at least one entry.

**Steps:**

1. Open an entry's details (JN-VT-007).
2. Tap **Edit entry**.
3. Modify one or more fields.
4. Tap **Save**.

**Expected result:**

- Updated values are reflected in the entry list and the details.

---

### JN-VT-009: Delete a vault entry

**Preconditions:** The vault is unlocked and has at least one entry.

**Steps:**

1. Open an entry's details (JN-VT-007).
2. Tap **Delete entry**.
3. Confirm the deletion prompt.

**Expected result:**

- The entry is removed from the list.
- It cannot be recovered from the UI.

---

### JN-VT-010: Generate a password for a new entry

**Preconditions:** The vault is unlocked. The new entry form is open.

**Steps:**

1. Tap **Generate password** on the password field.

**Expected result:**

- A strong random password is inserted into the password field.
- Tapping again replaces it with another.

---

### JN-VT-011: Create a vault folder

**Preconditions:** The vault is unlocked.

**Steps:**

1. Navigate to `/vault`.
2. Tap **New folder** in the top bar.
3. Enter a folder name.
4. Tap **Create**.

**Expected result:**

- The dialog closes and the new folder appears as a chip above the entry list.
- The folder is empty.
- **Create** stays disabled while the name is blank.

**Notes:**

- The folder is saved as an encrypted item, like an entry. Its name never reaches the Quark in the clear.
- If the save fails, the dialog stays open with the name and says why.
- An import also makes the folders its file names (JN-VT-017).

---

### JN-VT-012: Assign an entry to a folder

**Preconditions:** The vault has a folder (JN-VT-011). At least one entry exists.

**Steps:**

1. Open the entry form (new or edit).
2. Select the target folder in the **Folder** field.
3. Tap **Save**.

**Expected result:**

- The entry appears under the selected folder when filtered (JN-VT-013).
- It is still listed when no folder is chosen.

**Notes:**

- With no folders the form has no **Folder** field.

---

### JN-VT-013: Filter entries by folder

**Preconditions:** The vault is unlocked. Entries exist in at least one folder.

**Steps:**

1. Navigate to `/vault`.
2. Tap a folder chip above the list.

**Expected result:**

- Only entries in the selected folder are shown.
- Entries in other folders are hidden.
- The **All** chip shows every entry again.

---

### JN-VT-014: Search vault entries

**Preconditions:** The vault is unlocked and has multiple entries.

**Steps:**

1. Type a search query into the search field.

**Expected result:**

- The list is filtered to entries whose name, URL host or username holds the query, ignoring case.
- Clearing the query restores the full list.

**Notes:**

- Search runs in the app over the decrypted entries. Nothing is sent to the Quark.

---

### JN-VT-015: Export vault entries as JSON

**Preconditions:** The vault is unlocked and has at least one entry.

**Steps:**

1. Tap **Export** in the top bar.
2. Select **Export as JSON**.

**Expected result:**

- `quark_vault.json` is downloaded or saved to the client device, and a snack bar says so.
- The file holds every entry and folder in plaintext, and an import reads it back (JN-VT-017).

**Notes:**

- The export is written in the app from the unlocked vault and is not encrypted. Keep the file somewhere safe.

---

### JN-VT-016: Export vault entries as CSV

**Preconditions:** The vault is unlocked and has at least one entry.

**Steps:**

1. Tap **Export** in the top bar.
2. Select **Export as CSV**.

**Expected result:**

- `quark_vault.csv` is downloaded or saved to the client device.
- The file holds one row per entry under a `name,url,username,password,notes,totp_secret,folder` header, in
  plaintext.

---

### JN-VT-017: Import vault entries

**Preconditions:** The vault is unlocked. An export file is available: a Quark JSON export, a Bitwarden CSV, a Proton
Pass CSV (Settings › Export › CSV), a Google Password Manager CSV (`chrome://password-manager/settings` › Export
passwords), or another manager's CSV.

**Steps:**

1. Tap **Import** in the top bar.
2. Choose the import file.

**Expected result:**

- Imported entries appear in the vault list.
- Entries that already exist (same name and site) are skipped, not duplicated or overwritten.
- Folders the file names are made as they are needed.
- From Proton Pass, a login saved with only an email keeps the email as its username, and its one-time-code secret
  and Proton vault (as a folder) come along. Notes, aliases and cards are left out and counted in the summary, not
  reported as errors.
- The snack bar reads, for example, "Imported 2 entries, 1 skipped (duplicates), 3 non-login items left out".

**Notes:**

- The format is recognized from the file: JSON by its first character, Bitwarden and Proton Pass by their CSV
  headers, and any other CSV by its column names.
- The file is read and encrypted in the app. The Quark receives each entry as ciphertext.

---

### JN-VT-018: Change vault password (retired)

Retired by #3456: the vault has no password of its own. It opens with the login password, and changing that keeps
the vault (JN-VT-020).

---

### JN-VT-019: Restore the vault from a backup drive (retired)

Retired by #3460: the app no longer offers this. On a SQLite-backed Quark a snapshot backup (JN-SD-008) copies
every account's vault, as ciphertext with its wrapped key, into `vault_items_backup.db` and asks for no password; on
PostgreSQL the vault is in the operator's database backup instead. Restoring that file waits on
the restore route chat restore will use (#2428). `POST /api/v0/vault/import-backup` is gone, and a
`vault_backup.db` from an older snapshot can no longer be restored.

---

### JN-VT-020: Changing the login password keeps the vault

**Preconditions:** The account has a vault with at least one entry.

**Steps:**

1. Navigate to `/settings/account` and tap **Change password**.
2. Enter the current password and a new one, and confirm.
3. Navigate to `/vault`, lock the vault if it is unlocked (JN-VT-005), and unlock it with the new password.
4. Lock it again and try the old password.

**Expected result:**

- Step 3 unlocks the vault, and every entry is still there.
- Step 4 shows "That password doesn't unlock your vault."

**Notes:**

- The app opens the vault key with the current password and sends it back wrapped under the new one, in the same
  request that changes the password. The entries themselves are not touched.
- A recovery with the recovery phrase (JN-AUTH-005) keeps the vault the same way, as long as the vault key has a
  phrase wrap: the phrase was typed at setup (JN-VT-001), or the account has been given a new phrase since. Without
  one, nothing the account still holds opens the vault, and JN-VT-021 is the way out.

---

### JN-VT-021: Start over when the password no longer opens the vault

**Preconditions:** The account has a vault that its current login password does not open, such as one set up before
a recovery that could not carry it over.

**Steps:**

1. Navigate to `/vault`.
2. Tap **Start over** under the unlock form.
3. Read the confirmation, then tap **Delete vault**.

**Expected result:**

- The confirmation says every saved login is deleted, on every device, and nobody can get them back.
- After confirming, the app shows **Set up your vault** (JN-VT-001).
- Canceling leaves the vault as it was.

**Notes:**

- Nobody, an admin included, can recover a vault the account's password and recovery phrase no longer open. This is
  the only way out.
- The account's other open sessions lock and show the setup screen too.

---

### JN-VT-022: Delete a vault folder

**Preconditions:** The vault is unlocked and has a folder with at least one entry in it (JN-VT-012).

**Steps:**

1. Navigate to `/vault`.
2. Tap the folder's chip.
3. Tap **Delete folder** at the end of the chip row.
4. Confirm with **Delete**.

**Expected result:**

- The confirmation says the folder is removed on every device and the logins in it are kept, in no folder.
- After confirming, the folder's chip is gone and the filter is back on **All**.
- The folder's entries are still listed, and their details no longer name a folder.
- Canceling leaves the folder as it was.

**Notes:**

- **Delete folder** shows only while a folder is chosen.
