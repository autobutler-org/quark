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

**Preconditions:** No account named `dee` exists.

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

**Preconditions:** A folder `users/eli` exists with files in it. No account is named `eli`.

**Steps:**

1. Navigate to `/users`.
2. Tap **Add user**, and enter `eli` with a password.
3. Tap **Add user** in the dialog.

**Expected result:**

- The account is created, and `users/eli` becomes its home with everything already in it.
- `eli` owns `users/eli` and can upload to it.

**Notes:**

- The accounts, not the folders, decide whether a username is taken. An admin can make `users/eli` and fill it
  before the account exists; whoever gets the name `eli` gets that folder.
- A taken username shows "That username is taken." and the dialog stays open with what was typed.

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
- A home of that name that already exists becomes theirs, with whatever is in it. An account is never approved
  without a home it owns.

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
- A folder named `Family` is made in `groups`, which the group can write to. Everyone added to the group reaches it
  (JN-FB-035); nobody else does.
- After step 3 the dialog stays open and reads "A group with that name already exists.": names are unique ignoring
  case.

**Notes:**

- A name has 1 to 64 characters, isn't `.` or `..`, and has no slashes, line breaks or tabs. It is also the name of
  the group's folder, so it has to be one folder name.
- A folder of that name already sitting in `groups` is adopted, with its content, rather than refused.

---

### JN-USR-017: Rename a group

**Preconditions:** A group named `Family` exists.

**Steps:**

1. On the **Groups** tab, tap the actions menu on **Family**'s row.
2. Tap **Rename**, change the name to `Household`, and tap **Rename**.
3. Make a folder called `Neighbors` in `groups` (JN-FB-009), then rename **Household** to `Neighbors`.

**Expected result:**

- The row reads **Household**, with the same members.
- Whatever was shared with the group is still shared with it.
- The group's folder is renamed to match, the way any other move goes: what is shared on it, the favorites in it and
  its album items all follow, and open clients see the move without a refresh (JN-FB-024).
- Step 3 is refused with "a folder with that name is already in groups; move or rename it first", and the group keeps
  the name it had.

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
- The group's folder in `groups`, and everything in it, stay too. With the group gone only an admin reaches that
  folder, to hand it to someone else (JN-FB-027) or to remove it.
- Tapping **Cancel** in step 2 changes nothing.

---

### JN-USR-020: The everyone group has a folder

**Preconditions:** User is signed in as an admin. A second account, `bob`, is not an admin.

**Steps:**

1. Navigate to `/files` and open `groups`.
2. Open `everyone` and upload a file into it (JN-FB-006).
3. Sign in as `bob` and tap **Groups**.

**Expected result:**

- `groups/everyone` exists without anyone having made it, and every account can read and write in it — a shared
  drawer nobody has to be added to.
- bob sees `everyone` among his group folders and can open the uploaded file.

**Notes:**

- The quark gives any group with no folder one at startup, so a Quark upgraded from before group folders gets
  `everyone` and a folder for each group it already had.
- A group named before names had to be one folder name — one holding a slash — keeps no folder rather than being
  given one somewhere else in the tree.
