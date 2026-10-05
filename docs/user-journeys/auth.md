# Auth Journeys

Covers first-boot setup, login, logout, and password recovery.

---

### JN-AUTH-001: First-boot setup — create account

**Preconditions:** Quark is freshly installed and has no owner account. App is opened for the first time.

**Steps:**

1. Open the app.
2. App detects no setup and navigates to `/setup`.
3. Enter a username (e.g. `alice`).
4. Enter a password.
5. Re-enter the password in the confirm field.
6. Tap **Create account**.
7. A recovery phrase is displayed (6 words).
8. Copy or write down the phrase.
9. Check the acknowledgement checkbox ("I've saved my recovery phrase").
10. Tap **Continue**.
11. App presents a theme selection step (light / dark / system).
12. Choose a theme.
13. Tap **Done** (or equivalent).

**Expected result:**

- App navigates to `/files` (file browser), which greets the new owner with the welcome card (JN-FB-041).
- The username is accepted and the account is live on the quark.
- The theme chosen is applied immediately.

**Notes:**

- Recovery phrase is shown exactly once and is not recoverable from the UI after dismissal.
- The app makes the phrase, not the Quark, and sends the Quark only a key derived from it (#2430).
- Weak password or mismatched confirm should show inline validation errors before submit.
- Username uniqueness is enforced server-side; duplicate should surface an error on step 6.

---

### JN-AUTH-002: Login with correct credentials

**Preconditions:** Quark is set up (JN-AUTH-001 complete). User is not logged in.

**Steps:**

1. Open the app (or navigate to `/login`).
2. Enter the registered username.
3. Enter the correct password.
4. Tap **Log in**.

**Expected result:**

- App navigates to `/files`, which says "Welcome back" once (JN-FB-042).
- Session token is stored; subsequent navigation does not require re-login.
  Quark

---

### JN-AUTH-003: Login with wrong password

**Preconditions:** Quark is set up. User is not logged in.

**Steps:**

1. Navigate to `/login`.
2. Enter the registered username.
3. Enter an incorrect password.
4. Tap **Log in**.

**Expected result:**

- An error message appears below the form (not a blank screen or crash).
- User remains on the login page.
- Password field is not auto-cleared (user can correct and retry).

---

### JN-AUTH-004: Toggle password visibility on login screen

**Preconditions:** User is on the `/login` page.

**Steps:**

1. Enter any text in the password field.
2. Tap the eye icon next to the password field.

**Expected result:**

- Password characters become visible.
- Tapping the icon again hides them.

---

### JN-AUTH-005: Recover account with valid phrase

**Preconditions:** Quark is set up. User has their recovery phrase.

**Steps:**

1. Navigate to `/login`, optionally typing a username.
2. Tap **Forgot password** (or equivalent link).
3. App navigates to `/recover` (the address bar reads `/recover`), with the username field prefilled from the login
   form when one was typed. Opening `/forgot-password` directly lands here too.
4. Enter or confirm the username.
5. Enter that account's recovery phrase.
6. Enter a new password.
7. Confirm the new password.
8. Tap **Reset password**.

**Expected result:**

- App navigates to `/login` (or directly to `/files` on auto-login).
- The named account can log in with the new password.
- That account's old password no longer works.
- Every other account's password is unchanged.
- Before step 8, browser Back or **Back to sign in** returns to `/login`.

**Notes:**

- Recovering never sends the new password to the Quark, only a key derived from it (#2430).
- An account whose phrase the Quark made, and that has not yet signed in from an updated app (JN-AUTH-016), sends
  that phrase this once and is shown a new recovery phrase after step 8, with the same acknowledgment checkbox and
  **Continue**; Back stays on the phrase until then. The old phrase stops working.
- Once an account has a phrase the app made, recovering it sends only a key derived from the phrase, unless the
  Quark answers that the account has none, as a reset Quark does; then the phrase goes out that once, as above.

---

### JN-AUTH-006: Recover account with invalid phrase

**Preconditions:** User is on `/recover`.

**Steps:**

1. Enter a username with a recovery phrase that is not that account's, or a username that does not exist.
2. Enter a new password and confirm.
3. Tap **Reset password**.

**Expected result:**

- An error message appears. It is the same for an unknown username and a wrong phrase, so it does not reveal
  which usernames exist.
- No account's password is changed.
- User remains on the recover page.

---

### JN-AUTH-007: Sign out

**Preconditions:** User is logged in and on any page.

**Steps:**

1. Open the navigation drawer.
2. Navigate to **Settings**, then the **Account** tab (`/settings/account`).
3. Tap **Sign out**.

**Expected result:**

- Session token is cleared.
- App redirects to `/login`.
- Navigating back does not bypass the login page.

---

### JN-AUTH-008: Terms of service gate

**Preconditions:** App has a host configured but user has not yet accepted terms.

**Steps:**

1. Open the app.

**Expected result:**

- App navigates to `/terms` before any other protected route.
- The page opens with a plain-language summary — files stay on your hardware, keep your own backup, it is
  for your household — above the full terms, marked as a summary rather than the agreement (#2027).
- User must accept before accessing `/files` or any other feature.

---

### JN-AUTH-009: Request an account

**Preconditions:** Quark is set up and takes account requests (the default). User is not signed in and has no
account on this Quark.

**Steps:**

1. Navigate to `/login`.
2. Tap **Need an account? Request one**.
3. App navigates to `/request-account`.
4. Enter a username, for example `bob`.
5. Enter a password, and enter it again to confirm.
6. Tap **Send request**.
7. The recovery phrase for the new account is displayed.
8. Check the acknowledgment checkbox.
9. Tap **Continue**.

**Expected result:**

- A **Request sent** state explains that an admin of this Quark needs to approve the request.
- **Back to sign in** returns to `/login`.
- The request appears on an admin's Users page.

**Notes:**

- A username must be up to 32 lowercase letters, numbers, dots, dashes or underscores, starting with a letter or
  number. The form says so before sending, and does not lowercase what was typed. The same rule applies on
  `/setup`.
- A username already taken, including by another pending request, is refused with "That username is taken."
- The admin never sees the recovery phrase, and nor does the Quark: the app makes it (#2430).

---

### JN-AUTH-010: Sign in while the request is pending

**Preconditions:** JN-AUTH-009 complete. No admin has approved the request.

**Steps:**

1. Navigate to `/login`.
2. Enter the requested username and its password.
3. Tap **Sign in**.

**Expected result:**

- The form shows "Your account request hasn't been approved yet. Ask an admin of this Quark."
- User remains on the login page, with no session.

**Notes:**

- A wrong password for a pending account still shows "Invalid username or password.", so a sign-in attempt does
  not reveal which usernames have been requested.

---

### JN-AUTH-011: Sign in after the request is approved

**Preconditions:** JN-AUTH-009 complete. An admin has approved the request (JN-USR-008).

**Steps:**

1. Navigate to `/login`.
2. Enter the requested username and its password.
3. Tap **Sign in**.

**Expected result:**

- App navigates to `/files`.
- The account's recovery phrase from JN-AUTH-009 resets its password (JN-AUTH-005).

---

### JN-AUTH-012: Requests turned off

**Preconditions:** An admin has turned off account requests (JN-USR-010). User is not signed in.

**Steps:**

1. Navigate to `/login`.

**Expected result:**

- The sign-in form does not offer to request an account.
- Opening `/request-account` directly and sending a request shows "This Quark isn't taking account requests right now."

---

### JN-AUTH-013: First sign-in of an account an admin added

**Preconditions:** An admin added the account (JN-USR-006). It has never signed in.

**Steps:**

1. Navigate to `/login`.
2. Enter the username and the initial password the admin gave you.
3. Tap **Sign in**.
4. The account's recovery phrase is displayed.
5. Check the acknowledgment checkbox.
6. Tap **Continue**.

**Expected result:**

- App navigates to `/files`, which says "Welcome back" once (JN-FB-042).
- Signing in again later goes straight to `/files`, with no phrase.
- The phrase shown is one the app made at this sign-in, not one the Quark made when the account was added (#2430).

**Notes:**

- The app is not signed in until **Continue**. Leaving the phrase screen before then means signing in again, and the
  phrase is not shown a second time: as with setup, a phrase lost before it was saved stays lost.

---

### JN-AUTH-014: Sign in to a turned-off account

**Preconditions:** An admin has turned the account off.

**Steps:**

1. Navigate to `/login`.
2. Enter that account's username and password.
3. Tap **Sign in**.

**Expected result:**

- The form shows "This account is turned off. Ask an admin of this Quark."
- User remains on the login page, with no session.

**Notes:**

- Recovering the account with its phrase is refused the same way.

---

### JN-AUTH-015: The last admin cannot delete their account while others remain

**Preconditions:** Signed in as the only active admin. At least one other active or turned-off account exists.

**Steps:**

1. Navigate to **Settings**, then the **Account** tab (`/settings/account`).
2. Tap **Account and data**, then **Delete account**, and confirm with your password (JN-ST-026).

**Expected result:**

- The deletion is refused with "This Quark needs at least one admin. Make someone else an admin first."
- Nothing is deleted, and you stay signed in.

**Notes:**

- When the only other accounts are pending requests, the deletion goes ahead: the requests are deleted with it, the
  Quark returns to setup, and the files are kept.

---

### JN-AUTH-016: New recovery phrase at the next sign-in

**Preconditions:** An account with no recovery phrase the app made: one whose phrase the Quark made, set up,
requested or added before #2430. It may never have signed in from an updated app. An admin-added account's first
sign-in is the same step (JN-AUTH-013).

**Steps:**

1. Navigate to `/login`.
2. Enter the username and password.
3. Tap **Sign in**.
4. A new recovery phrase is displayed.
5. Check the acknowledgment checkbox.
6. Tap **Continue**.

**Expected result:**

- App navigates to `/files`.
- The new phrase resets the password (JN-AUTH-005), and the old phrase no longer does.
- Signing in again later goes straight to `/files`, with no phrase.

**Notes:**

- If the Quark does not take the new phrase, nothing is shown, the sign-in goes ahead, and the old phrase keeps
  working. The next sign-in tries again.
- An account that never signed in from an updated app sends its password this once, beside the key derived from it,
  and the Quark moves it to the key and forgets the password (JN-AUTH-017).

---

### JN-AUTH-017: The sign-in form works for every account; old apps are told to update

**Preconditions:** One of: an account that never signed in from an app that sends an auth key (#2430); an app
from before auth keys; or a Quark that has not been updated to take auth keys.

**Steps:**

1. Navigate to `/login`.
2. Enter the username and password.
3. Tap **Sign in**.

**Expected result:**

- For the old account: the sign-in goes ahead, as for any account. The app sends the password once, beside the key
  derived from it, and the Quark moves the account to the key and forgets the password. Every later sign-in sends
  only the key. If the Quark cannot store the key, the sign-in fails and nothing changes.
- For an old app: the Quark answers with its own "This version of the app is too old for this Quark. Update the app
  to continue." The same goes for an old app's setup, account request, recovery and re-confirmations.
- For an old Quark: "This Quark needs an update before this app can sign in to it. Update the Quark, then try
  again." The app stays on `/login`, and nothing but the salt lookup was sent: never the password.

**Notes:**

- A Quark that answers that an account is old always gets the password once, beside the key, even from a device
  that signed in to it with the key before, since a reset or reinstalled Quark answers that way.
- An old account still holding a session from an older app, asked for its password again (deleting the account, a
  drive's role, the vault's storage location), is told "Sign out and sign in again, then try this again.", since
  only the sign-in form moves it to a key.

---

### JN-AUTH-018: Repeated wrong passwords lock sign-in out for a while

**Preconditions:** Quark is set up. User is not logged in.

**Steps:**

1. Navigate to `/login`.
2. Enter a username and a wrong password, and tap **Log in**, five times.
3. Enter the right password and tap **Log in**.

**Expected result:**

- The first five attempts show the usual wrong-password error (JN-AUTH-003).
- The sixth is refused with an error asking you to wait and try again, even though the password is right. No
  session is created.
- After 30 seconds the right password signs in. Each further miss before then doubles the wait, up to 15 minutes.

**Notes:**

- A username that doesn't exist is locked out exactly the same way, so the lockout does not reveal which accounts
  are real.
- The lockout covers that username from that address. Twenty misses from one address lock it out of every
  username; fifty misses on one username from anywhere lock it out of addresses it has never signed in from, while an
  address it has signed in from still gets through.
- Lockouts are held in memory only. A restart of the Quark clears them, and none travel with a drive moved to another
  Quark.
