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

- App navigates to `/files` (file browser).
- The username is accepted and the account is live on the quark.
- The theme chosen is applied immediately.

**Notes:**

- Recovery phrase is shown exactly once and is not recoverable from the UI after dismissal.
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

- App navigates to `/files`.
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
3. App navigates to `/recover`, with the username field prefilled from the login form when one was typed.
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
2. Navigate to **Settings** (`/settings`).
3. Scroll to the sign-out section.
4. Tap **Sign out**.

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
- The admin never sees the recovery phrase.

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

- App navigates to `/files`.
- Signing in again later goes straight to `/files`, with no phrase.

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
