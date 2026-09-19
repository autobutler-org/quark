# Users Journeys

Covers the admin-only Users page (`/users`): the accounts on a Quark, and what an admin can do with each.

Every journey assumes the user is signed in as an admin unless its preconditions say otherwise.

---

### JN-USR-001: Open the Users page

**Preconditions:** User is signed in as an admin.

**Steps:**

1. Open the navigation drawer.
2. Tap **Users**.

**Expected result:**

- App navigates to `/users`, open on the **Accounts** tab. The **Groups** tab is beside it (JN-USR-015).
- The **Accounts** section lists every account on the Quark. Admins are marked **Admin**, and turned-off accounts
  **Turned off**.
- The signed-in account is marked **You** and has no actions menu.

**Notes:**

- The list refreshes on its own when any admin, on any client, changes an account.

---

### JN-USR-002: A non-admin has no Users page

**Preconditions:** User is signed in to an account that is not an admin.

**Steps:**

1. Open the navigation drawer.
2. Type `/users` into the address bar.

**Expected result:**

- The drawer has no **Users** entry.
- Opening `/users` directly lands on `/files`.

**Notes:**

- The redirect asks the Quark whether the account is an admin, so an admin opening a `/users` link lands on the page.
- The Quark refuses every account request from a non-admin with 403 either way.

---

### JN-USR-003: Make someone an admin

**Preconditions:** Another active account exists that is not an admin.

**Steps:**

1. Navigate to `/users`.
2. Tap the actions menu on that account's row.
3. Tap **Make admin**.

**Expected result:**

- The row is marked **Admin**.
- That person's drawer gains **Users** and **Vault** without signing out.

---

### JN-USR-004: Remove an admin

**Preconditions:** Another admin exists besides the signed-in one.

**Steps:**

1. Navigate to `/users`.
2. Tap the actions menu on the other admin's row.
3. Tap **Remove admin**.

**Expected result:**

- The row is no longer marked **Admin**.
- That person loses **Users** and **Vault** from their drawer without signing out, and is moved to `/files` if they
  were on one of those pages.

---

### JN-USR-005: The last admin stays an admin

**Preconditions:** The signed-in account is the only admin on the Quark.

**Steps:**

1. Navigate to `/users`.
2. Find your own row.

**Expected result:**

- Your row, marked **You · Admin**, has no actions menu, so nothing on this page can leave the Quark without an admin.

**Notes:**

- The Quark enforces the same rule: removing the last active admin is refused with 409, which the app shows as "This
  Quark needs at least one admin. Make someone else an admin first."

---

### JN-USR-006: Add a user

**Preconditions:** No account named `dee` exists, and neither does a home at `users/dee`.

**Steps:**

1. Navigate to `/users`.
2. Tap **Add user**.
3. Enter `dee` as the username, and an initial password twice.
4. Tap **Add user** in the dialog.

**Expected result:**

- The dialog closes and `dee` appears in **Accounts**.
- A folder `users/dee` exists in Files, owned by `dee`.
- `dee` can sign in with that password, and sees their recovery phrase once (JN-AUTH-013).

**Notes:**

- The admin never sees the recovery phrase.
- Homes live under `users/`, so a top-level folder named `dee` is a different thing and does not stop the account
  being created.
- A username must be up to 32 lowercase letters, numbers, dots, dashes or underscores, starting with a letter or
  number. The dialog says so before sending.

---

### JN-USR-007: Adding a user whose folder already exists

**Preconditions:** A folder `users/eli` exists. No account is named `eli`.

**Steps:**

1. Navigate to `/users`.
2. Tap **Add user**, and enter `eli` with a password.
3. Tap **Add user** in the dialog.

**Expected result:**

- The dialog stays open with what was typed, and shows "A folder with that name already exists."
- No account is created, and the existing folder is not handed to anyone.

**Notes:**

- Only a home at `users/eli` refuses the account. A top-level folder named `eli` is a different thing and is left
  alone.
- A taken username shows "That username is taken." the same way.

---

### JN-USR-008: Approve an account request

**Preconditions:** Someone has requested an account (JN-AUTH-009).

**Steps:**

1. Navigate to `/users`.
2. In **Requests**, find the requested username.
3. Tap **Approve**.

**Expected result:**

- The request leaves **Requests** and the account appears in **Accounts**.
- The requester can sign in (JN-AUTH-011).
- A folder `users/<username>` exists in Files, owned by them, so their first upload lands somewhere.

**Notes:**

- The list refreshes on its own when a new request arrives, on any client.
- A home of that name already existing leaves the request pending and shows "A folder with that name already
  exists." An account is never approved without a home it owns.

---

### JN-USR-009: Deny an account request

**Preconditions:** Someone has requested an account (JN-AUTH-009).

**Steps:**

1. Navigate to `/users`.
2. In **Requests**, find the requested username.
3. Tap **Deny**.

**Expected result:**

- The request leaves **Requests** and no account is created.
- The username is free again at once: a new request or an admin-created account can take it.

---

### JN-USR-010: Turn account requests off

**Preconditions:** Account requests are on (the default).

**Steps:**

1. Navigate to `/users`.
2. Turn off **Allow account requests**.

**Expected result:**

- The switch stays off after a refresh.
- The sign-in page no longer offers to request an account (JN-AUTH-012).
- Requests already waiting stay in **Requests** and can still be approved or denied.

---

### JN-USR-011: Turn an account off

**Preconditions:** Another active account exists.

**Steps:**

1. Navigate to `/users`.
2. Tap the actions menu on that account's row.
3. Tap **Turn off**.

**Expected result:**

- The row is marked **Turned off**.
- That person is signed out everywhere, and signing in shows "This account is turned off. Ask an admin of this
  Quark." (JN-AUTH-014).
- Their files and shares stay as they were.

---

### JN-USR-012: Turn an account back on

**Preconditions:** JN-USR-011 complete.

**Steps:**

1. Navigate to `/users`.
2. Tap the actions menu on the turned-off account's row.
3. Tap **Turn on**.

**Expected result:**

- The row is no longer marked **Turned off**.
- That person can sign in again, with everything they had.

---

### JN-USR-013: Delete an account

**Preconditions:** Another account exists that owns a folder.

**Steps:**

1. Navigate to `/users`.
2. Tap the actions menu on that account's row.
3. Tap **Delete**.
4. Read the confirmation, and tap **Delete**.

**Expected result:**

- The account leaves **Accounts** and can no longer sign in.
- The folders it owned stay where they are, and the signed-in admin now owns them, including anything of theirs in
  the trash.
- Tapping **Cancel** in step 4 changes nothing.

---

### JN-USR-014: Your own account has no actions here

**Preconditions:** User is signed in as an admin.

**Steps:**

1. Navigate to `/users`.
2. Find your own row.

**Expected result:**

- Your row, marked **You**, has no actions menu: turning off or deleting your own account happens from Settings.

**Notes:**

- The Quark refuses an admin action on the caller's own account with "Use Settings to change your own account."

---

### JN-USR-015: See the groups

**Preconditions:** User is signed in as an admin.

**Steps:**

1. Navigate to `/users`.
2. Tap the **Groups** tab.

**Expected result:**

- **everyone** is listed first and reads **Every account**. It has no actions menu: every account is in it, so it
  can't be renamed or deleted, and its members can't be changed.
- Every other group is listed by name, with how many members it has.

**Notes:**

- The list refreshes on its own when any admin, on any client, changes a group or who is in one.

---

### JN-USR-016: Create a group

**Preconditions:** User is on the **Groups** tab.

**Steps:**

1. Tap **New group**.
2. Type `Family` and tap **Create**.
3. Tap **New group** again, type `family`, and tap **Create**.

**Expected result:**

- After step 2 the dialog closes, and **Family** is listed with **No members**.
- After step 3 the dialog stays open and reads "A group with that name already exists.": names are unique ignoring
  case.

**Notes:**

- A name has 1 to 64 characters and no line breaks or tabs.

---

### JN-USR-017: Rename a group

**Preconditions:** A group named `Family` exists.

**Steps:**

1. On the **Groups** tab, tap the actions menu on **Family**'s row.
2. Tap **Rename**, change the name to `Household`, and tap **Rename**.

**Expected result:**

- The row reads **Household**, with the same members.
- Whatever was shared with the group is still shared with it.

---

### JN-USR-018: Add and remove group members

**Preconditions:** A group named `Family` exists, along with an active account `bob` and a turned-off account `cy`.

**Steps:**

1. On the **Groups** tab, tap the actions menu on **Family**'s row, then **Members**.
2. Search for `bob` and tap his row.
3. Tap the remove button on **bob**'s row in the members list.

**Expected result:**

- The picker lists only accounts that can sign in and aren't already members, so `cy` isn't offered.
- After step 2 **bob** is listed as a member, the picker stops offering him, and **Family**'s row reads **1 member**.
- Whatever is shared with **Family** appears in bob's Files without a refresh (JN-FB-024).
- After step 3 bob is no longer a member, and what was shared with **Family** leaves his Files.

**Notes:**

- If the account stops being able to sign in before it is added, the sheet reads "That account can't join a group.
  Only accounts that can sign in can be added."
- A turned-off account that was already a member stays one.

---

### JN-USR-019: Delete a group

**Preconditions:** A group named `Family` exists, and a folder is shared with it.

**Steps:**

1. On the **Groups** tab, tap the actions menu on **Family**'s row, then **Delete**.
2. Read the confirmation, and tap **Delete**.

**Expected result:**

- **Family** leaves the list.
- Its members lose what was shared with **Family**. Their accounts and their own files stay.
- Tapping **Cancel** in step 2 changes nothing.
