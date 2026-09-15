# Vault Journeys

Covers the Vault (`/vault`) — password manager setup, entry management, folders, import/export.

The vault is admin-only (#1899): every journey in this file except JN-VT-000 assumes the user is signed in as an
admin.

---

### JN-VT-000: A non-admin cannot open the vault

**Preconditions:** User is signed in to an account that is not an admin.

**Steps:**

1. Open the navigation drawer.
2. Type `/vault` into the address bar.

**Expected result:**

- The drawer has no **Vault** entry.
- Opening `/vault` directly lands on `/files`.

**Notes:**

- The redirect asks the Quark whether the account is an admin, so an admin opening a `/vault` link lands on the vault
  (#1928).
- An admin demoted while on `/vault` is moved to `/files`.

---

### JN-VT-001: Set up the vault for the first time

**Preconditions:** Vault has never been initialized. A storage device is connected.

**Steps:**

1. Navigate to `/vault`.
2. App shows the vault setup screen (not unlock or entry list).
3. Enter a vault password.
4. Confirm the vault password.
5. Tap **Create vault**.

**Expected result:**

- Vault is initialized on the quark.
- App transitions to the unlocked entry list (empty).

---

### JN-VT-002: Vault requires device — no device connected

**Preconditions:** Vault has not been initialized. No storage device is connected.

**Steps:**

1. Navigate to `/vault`.

**Expected result:**

- A "device disconnected" message is shown.
- Setup is not possible until a device is connected.

---

### JN-VT-003: Unlock the vault

**Preconditions:** Vault is initialized and currently locked.

**Steps:**

1. Navigate to `/vault`.
2. Enter the vault password in the unlock field.
3. Tap **Unlock**.

**Expected result:**

- Vault unlocks and the entry list is displayed.
- Folders and entries are visible.

---

### JN-VT-004: Unlock with wrong password

**Preconditions:** Vault is initialized and locked.

**Steps:**

1. Navigate to `/vault`.
2. Enter an incorrect password.
3. Tap **Unlock**.

**Expected result:**

- Error message appears.
- Vault remains locked.

---

### JN-VT-005: Lock the vault

**Preconditions:** Vault is unlocked.

**Steps:**

1. Navigate to `/vault`.
2. Tap the **Lock** button.

**Expected result:**

- Vault transitions back to the locked/unlock-prompt state.
- Entry list is no longer visible.

---

### JN-VT-006: Add a new vault entry

**Preconditions:** Vault is unlocked.

**Steps:**

1. Navigate to `/vault`.
2. Tap the **Add entry** FAB or button.
3. Fill in: title, username, password, URL, notes (at minimum title).
4. Confirm / Save.

**Expected result:**

- New entry appears in the entry list.
- Entry details match what was entered.

---

### JN-VT-007: View an existing vault entry

**Preconditions:** Vault is unlocked and has at least one entry (JN-VT-006).

**Steps:**

1. Tap an entry in the list.

**Expected result:**

- Entry detail view opens showing all fields.
- Sensitive fields (password) are obscured by default.
- Copy-to-clipboard button is available for username and password.

---

### JN-VT-008: Edit a vault entry

**Preconditions:** Vault is unlocked and has at least one entry.

**Steps:**

1. Open an entry's detail view (JN-VT-007).
2. Tap **Edit**.
3. Modify one or more fields.
4. Save.

**Expected result:**

- Updated values are reflected in the entry list and detail view.

---

### JN-VT-009: Delete a vault entry

**Preconditions:** Vault is unlocked and has at least one entry.

**Steps:**

1. Open an entry's detail view (JN-VT-007).
2. Tap **Delete**.
3. Confirm the deletion prompt.

**Expected result:**

- Entry is removed from the list.
- It cannot be recovered from the UI.

---

### JN-VT-010: Generate a password for a new entry

**Preconditions:** Vault is unlocked. New entry editor is open.

**Steps:**

1. Tap the **Generate password** button in the entry editor.

**Expected result:**

- A strong random password is inserted into the password field.
- User can regenerate or accept it.

---

### JN-VT-011: Create a vault folder

**Preconditions:** Vault is unlocked.

**Steps:**

1. Navigate to `/vault`.
2. Tap **New folder** (or equivalent).
3. Enter a folder name.
4. Confirm.

**Expected result:**

- New folder appears in the sidebar or folder list.
- Folder is initially empty.

---

### JN-VT-012: Assign an entry to a folder

**Preconditions:** A vault folder exists (JN-VT-011). At least one entry exists.

**Steps:**

1. Open the entry editor (new or edit).
2. Select the target folder from the folder picker.
3. Save.

**Expected result:**

- Entry appears under the selected folder when filtered.
- Entry is hidden from the "All" or unfoldered view (or shown depending on filter).

---

### JN-VT-013: Filter entries by folder

**Preconditions:** Vault is unlocked. Entries exist in at least one folder.

**Steps:**

1. Navigate to `/vault`.
2. Select a folder from the sidebar.

**Expected result:**

- Only entries in the selected folder are shown.
- Entries in other folders are hidden.

---

### JN-VT-014: Search vault entries

**Preconditions:** Vault is unlocked and has multiple entries.

**Steps:**

1. Type a search query into the search field.

**Expected result:**

- List is filtered to entries matching the query (by title, URL, or username).
- Clearing the query restores the full list.

---

### JN-VT-015: Export vault entries as JSON

**Preconditions:** Vault is unlocked and has at least one entry.

**Steps:**

1. Open the vault overflow menu.
2. Select **Export → JSON**.

**Expected result:**

- A JSON file is downloaded or saved to the client device.
- File contains all vault entries in plaintext.

**Notes:**

- This is a sensitive operation. Warn the user that the export is unencrypted.

---

### JN-VT-016: Export vault entries as CSV

**Preconditions:** Vault is unlocked and has at least one entry.

**Steps:**

1. Open the vault overflow menu.
2. Select **Export → CSV**.

**Expected result:**

- A CSV file is downloaded or saved to the client device.
- File contains all vault entries.

---

### JN-VT-017: Import vault entries

**Preconditions:** Vault is unlocked. A valid import file (JSON or CSV) is available.

**Steps:**

1. Open the vault overflow menu.
2. Select **Import**.
3. Choose the import file.
4. Confirm.

**Expected result:**

- Imported entries appear in the vault list.
- Existing entries are not overwritten (or merge behavior is documented).

---

### JN-VT-018: Change vault password

**Preconditions:** Vault is unlocked.

**Steps:**

1. Navigate to vault settings (if available in UI) or relevant action.
2. Enter the current password.
3. Enter and confirm a new password.
4. Confirm.

**Expected result:**

- Vault can be unlocked using the new password.
- Old password no longer works.
