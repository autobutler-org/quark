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

- App navigates to `/users`.
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
