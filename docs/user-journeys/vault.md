# Vault Journeys

Covers the Vault (`/vault`) — password manager setup, entry management, folders, import/export, and filling
passwords on a phone.

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
  with that phrase keeps the vault (JN-VT-020). Nothing checks the phrase typed here against the Quark: a mistyped
  one is accepted and simply never opens the vault.
- A vault set up without the phrase has no phrase wrap, and a recovery cannot keep it. The open vault then offers
  **Add your recovery phrase** (JN-VT-023), which checks the phrase with the Quark before it adds the wrap.

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

Retired by #3460: the app no longer offers this. A snapshot backup (JN-SD-008) copies every account's vault, as
ciphertext with its wrapped key, into `vault_items_backup.db` and asks for no password. Restoring that file waits on
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
  phrase wrap: the phrase was typed at setup (JN-VT-001), it was added later (JN-VT-023), or the account has been
  given a new phrase since. Without one, nothing the account still holds opens the vault, and JN-VT-021 is the way
  out.

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
  the only way out. Adding the phrase while the password still opens the vault (JN-VT-023) is what keeps a later
  recovery from ending here.
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

---

### JN-VT-023: Add the recovery phrase to a vault set up without it

**Preconditions:** The account has a vault whose key has no phrase wrap: it was set up without the phrase
(JN-VT-001). The account has a recovery phrase.

**Steps:**

1. Navigate to `/vault` and unlock it (JN-VT-003).
2. The card **Add your recovery phrase** says "Add your recovery phrase so a recovery keeps your vault and
   messages."
3. Tap **Add phrase**.
4. Enter a phrase that is not the account's, and the password you sign in with, and tap **Add phrase**.
5. Correct the phrase and tap **Add phrase** again.

**Expected result:**

- Step 4 shows "That isn't your account's recovery phrase. Nothing was changed; check the words and try again." The
  dialog stays open with what was typed, and the vault, the chat keys and the account's phrase are unchanged.
- Step 5 closes the dialog, says "Recovery phrase added. A recovery now keeps your vault and messages.", and the card
  goes away.
- A recovery with that phrase (JN-AUTH-005) then keeps the vault (JN-VT-020) and the chat history.
- **Not now** hides the card until the app restarts.

**Notes:**

- The app opens the vault key and the chat keys with the password, wraps them under keys the phrase derives, and
  sends the Quark the phrase's recovery key and the new wraps. The Quark checks that recovery key against the one it
  holds before it stores anything, so a mistyped phrase never becomes a wrap and never replaces the account's
  phrase. Neither the phrase, the password nor the vault key is sent.
- Wrong phrases count toward the sign-in lockout (JN-AUTH-018).
- Chat keys made at a sign-in have no phrase wrap either, and chat offers the same card (JN-CHAT-021); adding the
  phrase from either page covers both.

---

<!-- cspell:words badexample -->

## Filling passwords on a phone

These journeys cover the phone apps only: filling saved logins into other apps and websites, and opening the vault
with a face or fingerprint, which filling depends on. Web and desktop do not offer any of it. How it works and what it
keeps on the phone is in [Native vault autofill](../architecture/vault-autofill.md).

None of these journeys has been run on a real phone yet; they are written from the code and its tests. On iPhone,
filling also waits on Apple signing for the AutoFill part of the app (#3662), so JN-VT-030 and JN-VT-033 cannot be run
on a store or TestFlight build until that lands.

---

### JN-VT-024: Turn on Face ID or fingerprint unlock for the vault

**Preconditions:** The phone app (iPhone, or Android 10 or later) is signed in, and the account has a vault. The phone
has a passcode and at least one face or fingerprint set up.

**Steps:**

1. Navigate to `/vault` and unlock it with the password (JN-VT-003).
2. The card **Unlock with Face ID?** (on Android, **Unlock with fingerprint or face?**) says "Open your vault on this
   device without typing your password." Tap **Turn on**. (After **Not now**, the fingerprint button in the top bar
   opens the same setting.)
3. Read the setting's explanation, then turn its switch on.
4. Pass the Face ID, Touch ID or fingerprint check.
5. Tap **Close**.

**Expected result:**

- Before anything is kept, the explanation says that the vault's key is kept in the phone's secure storage and asked
  for with Face ID (or the phone's own method) every time, that anyone who can pass that check on this phone can open
  the vault, that adding or removing a face or fingerprint turns it off, and that locking keeps it on while signing
  out, changing the password or starting over turns it off.
- After step 4 the switch stays on. Canceling the check leaves it off and shows nothing alarming.
- On Android, the vault now shows the **Fill passwords in other apps** card (JN-VT-027).

**Notes:**

- Off by default, and per phone: turning it on here does not turn it on anywhere else.
- Only the account signed in on the Quark in use is kept.
- A phone that cannot keep the key safely (no face or fingerprint set up, Android older than 10, or no secure
  hardware) shows no card and no button, or says "This device can't keep your vault behind a face or fingerprint.
  Check that one is set up in your device settings."
- There is no passcode fallback: the phone's passcode alone never opens the vault.

---

### JN-VT-025: Unlock the vault with Face ID or a fingerprint

**Preconditions:** Face ID or fingerprint unlock is on (JN-VT-024). The vault is locked (JN-VT-005).

**Steps:**

1. Navigate to `/vault`.
2. Tap **Unlock with Face ID** (Touch ID, or **Unlock with fingerprint or face** on Android) and pass the check.
3. Lock the vault again, open it, and tap **Use password instead**.

**Expected result:**

- The locked screen says "Open it with Face ID, or with the password you sign in to Quark with."
- Step 2 opens the vault with every entry, as the password does.
- Step 3 shows the password form (JN-VT-003).
- Locking, by hand or after 15 idle minutes, leaves the setting on.

**Notes:**

- After a face or fingerprint is added or removed on the phone, step 2 says "The faces or fingerprints on this device
  changed, so unlock with your password this time." and the setting turns off.
- After too many failed checks: "Too many tries. Unlock with your password for now."
- If the vault was replaced elsewhere (JN-VT-021 on another device): "Your vault has changed since this was turned on,
  so unlock it with your password this time."

---

### JN-VT-026: Turn off Face ID or fingerprint unlock

**Preconditions:** Face ID or fingerprint unlock is on (JN-VT-024).

**Steps:**

1. Unlock the vault and tap the fingerprint button in the top bar.
2. Turn the switch off, and tap **Close**.
3. Lock the vault.

**Expected result:**

- The locked screen offers only the password form.
- Filling in other apps (JN-VT-028, JN-VT-030) stops: it asks to open Quark instead (JN-VT-031).
- QuickType suggestions (JN-VT-033) turn off.

**Notes:**

- The same happens by itself after signing out (JN-VT-032), switching account or Quark, changing the password on
  this phone (JN-VT-020), starting over (JN-VT-021), and adding or removing a face or fingerprint on the phone.

---

### JN-VT-027: Choose Quark for autofill on Android

**Preconditions:** Android 10 or later. Fingerprint or face unlock is on (JN-VT-024).

**Steps:**

1. Navigate to `/vault` and unlock it.
2. The card **Fill passwords in other apps** says "Choose Quark for autofill, and your browser offers your saved
   logins after a fingerprint or face check." Tap **Turn on autofill**.
3. On the phone's autofill screen, choose **Quark** and confirm.
4. Go back to Quark.

**Expected result:**

- Step 2 opens the phone's own screen for choosing the autofill service.
- After step 4 the card reads **Autofill is on**, "Your browser offers your saved logins from Quark after a
  fingerprint or face check.", with a **Change** button.

**Notes:**

- The card shows only on Android, only while the vault is open, and only with fingerprint or face unlock on.
- Recent Chrome versions also need Chrome's own setting (Chrome **Settings > Autofill services > Autofill using another
  service**) before they use Quark. Quark does not say so yet.

---

### JN-VT-028: Fill a login in Chrome on Android

**Preconditions:** Quark is the autofill service (JN-VT-027). The vault has a login whose URL is the site being
visited, such as `https://bank.example`.

**Steps:**

1. In Chrome, open the site's sign-in page and tap the username or password box.
2. Tap the suggestion **Use a saved login for bank.example**.
3. Read the check's title, and pass the fingerprint or face check.
4. Pick the login.

**Expected result:**

- Step 3's title is "Fill your bank.example login into Chrome?"
- Step 4 fills the username and password.
- The suggestions show a login's name and username, never its password.
- Canceling the check fills nothing and shows nothing alarming.

**Notes:**

- A login saved for `example.com` also fills `accounts.example.com`; one for `example.com` never fills
  `badexample.com`.
- The same works in Firefox, Samsung Internet, Edge, Brave, DuckDuckGo, Vivaldi and Opera. Quark believes the website
  only from these browsers, and only when the browser is the real one.
- Filling works offline: it uses the copy of the vault the app last saw, still locked.

---

### JN-VT-029: Fill a login in another Android app

**Preconditions:** Quark is the autofill service (JN-VT-027). An app whose sign-in is for a website, such as a bank's
app for `bank.example`, and the website confirms that app (its `assetlinks.json` grants the app the right to sign-in
details). The vault has a login for that website.

**Steps:**

1. Open the app's sign-in screen and tap the username or password box.
2. Tap Quark's suggestion, and pass the check.
3. Pick the login.

**Expected result:**

- The check's title names the website and the app: "Fill your bank.example login into Bank?"
- Step 3 fills the login.
- An app the website does not confirm gets "Fill a saved login into Bank?" and only logins linked to that app, or
  "No saved login for Bank."
- An app Quark cannot check gets "Quark can't check this app, so it won't fill it", and a form whose website Quark
  cannot tell gets "Quark can't tell which website this is, so it won't fill it".

**Notes:**

- Quark matches an app by who signed it, never by its name or by the website it claims, so a look-alike app is not
  filled.
- Quark asks the website itself for its confirmation file, never Google, and remembers the answer for a day.
- Nothing in Quark can link a login to an app yet, and the browser extension drops such a link when it edits the
  login (quark-browser-extensions#185).

---

### JN-VT-030: Choose Quark for AutoFill on iPhone and fill a login

**Preconditions:** An iPhone build that carries the AutoFill part of Quark (see the note at the top of this section).
Face ID or Touch ID unlock is on (JN-VT-024). The vault has a login for a website, such as `https://bank.example`.

**Steps:**

1. In the iPhone's Settings, open **General > AutoFill & Passwords** (iOS 18 and later) or **Passwords > Password
   Options** (iOS 17 and earlier), and turn on **Quark**.
2. In Safari, open the site's sign-in page, tap the username box, and tap the passwords button above the keyboard.
   Choose **Quark**.
3. Pass Face ID or Touch ID, and pick the login.
4. Repeat in an app that signs in to the same website.

**Expected result:**

- Step 3 lists the logins for the site, each with its name and username, and fills the one picked.
- Step 4 works the same when the app is tied to that website.
- If the copy of the vault on the phone is more than a week old, the list ends with "Last updated <date>. Open Quark
  to refresh."
- Canceling Face ID fills nothing and shows nothing alarming.

**Notes:**

- Quark does not explain the Settings step in the app yet.
- Filling works offline, from the copy of the vault the app last saw.

---

### JN-VT-031: Filling while the vault cannot be opened, or has no login for the site

**Preconditions:** Quark is the autofill service on Android (JN-VT-027) or the AutoFill provider on iPhone
(JN-VT-030).

**Steps:**

1. Turn off Face ID or fingerprint unlock (JN-VT-026), then try to fill a login (JN-VT-028 or JN-VT-030).
2. Turn it on again, and try to fill on a site the vault has no login for.

**Expected result:**

- Step 1 on Android shows one suggestion, "Open Quark and unlock your vault to use autofill", which opens Quark and
  fills nothing.
- Step 1 on iPhone says "To fill passwords here, open Quark, unlock your vault, and turn on Face ID or Touch ID for
  it." There is no button: open Quark from the home screen.
- Step 2 says "No saved login for bank.example." and fills nothing.

**Notes:**

- After a face or fingerprint is added or removed: "Your fingerprints or face changed, so open Quark and unlock with
  your password once."
- Nothing is ever filled when Quark is unsure.

---

### JN-VT-032: Signing out stops autofill on this phone

**Preconditions:** Face ID or fingerprint unlock is on (JN-VT-024), and filling works (JN-VT-028 or JN-VT-030).

**Steps:**

1. In Quark, sign out (JN-AUTH-007).
2. Try to fill a login in a browser.
3. Sign in again and open the vault.

**Expected result:**

- Step 2 behaves as JN-VT-031 step 1: nothing fills.
- After step 3, the vault asks for the password, and Face ID or fingerprint unlock is off until it is turned on again.
- Switching to another account or another Quark does the same for the previous account.

**Notes:**

- Signing this phone out from another device (a password change or recovery there) stops autofill only the next time
  Quark runs on this phone. Until then it still fills, still behind a face or fingerprint check every time.

---

### JN-VT-033: QuickType suggestions on iPhone

**Preconditions:** An iPhone with Face ID or Touch ID unlock on (JN-VT-024) and Quark turned on for AutoFill
(JN-VT-030).

**Steps:**

1. Unlock the vault and tap the keyboard button in the top bar (**QuickType suggestions**).
2. Read the explanation, turn on **Show Quark logins in QuickType suggestions**, and tap **Close**.
3. In Safari, open a site the vault has a login for and tap the username box.
4. Tap the login the keyboard suggests, and pass Face ID.

**Expected result:**

- Before it is on, the explanation says that iOS keeps each login's site address and username unencrypted on the
  phone, outside the vault, that passwords stay encrypted, and that signing out, starting over or turning off Face ID
  unlock turns this off and removes them.
- Step 3's keyboard suggests the login. Step 4 fills it.
- Turning the setting off removes the suggestions.

**Notes:**

- Off by default, per phone. The button shows only on iPhone with Face ID or Touch ID unlock on.
- A suggestion for a login deleted since fills nothing.

---

### JN-VT-034: Save a new login from Android autofill

**Preconditions:** Android 10 or later, Quark is the autofill service (JN-VT-027), and the vault has no login for the
site.

**Steps:**

1. In Chrome, sign in to a site with a username and password typed by hand, where Quark offered its suggestion.
2. When the phone offers to save the login to Quark, accept.
3. Read the check's title and pass the fingerprint or face check.
4. Open Quark and unlock the vault.

**Expected result:**

- Step 3's title is "Save your bank.example login to Quark?"
- After step 3: "Saved. It goes into your vault the next time you open Quark."
- After step 4 the login is in the vault, and on every other device.
- Saving a login the vault already has says "This login is already in your vault." and saves nothing.

**Notes:**

- Quark offers to save only where it would also fill: a website a trusted browser reported, or an app it can check.
- Until the vault is opened, the login waits on the phone, locked. With 50 logins waiting, Quark says "Quark has logins
  waiting to go into your vault. Open Quark and unlock your vault, then try again."
- A form with two different passwords (changing a password) is not offered for saving.
