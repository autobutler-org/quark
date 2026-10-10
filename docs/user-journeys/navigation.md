# Navigation Journeys

Covers the navigation drawer every top-level page opens from its brand button: which destinations it lists, in what
order, and which ones a given account sees.

---

### JN-NV-001: The drawer leads with the household's pages

**Preconditions:** Logged in as an admin, with the Calendar, Slides and Chat betas on (JN-ST-028 turns one off).

**Steps:**

1. On Files, tap the brand button to open the drawer.
2. Read the rows from top to bottom, scrolling if the screen is shorter than the list.
3. Tap **Photos**, then open the drawer again.

**Expected result:**

- Under the header that names the Quark, the everyday pages come first, in this order: **Files**, **Photos**,
  **Calendar**, **Docs**, **Sheets**, **Slides**, **Books**, **Chat**, **Vault**.
- A hairline and a **Manage** heading follow, then the pages for looking after the Quark: **Trash**, **System**,
  **Users**, **Settings**.
- **Manage** is a heading, not a row: tapping it does nothing, and a screen reader announces it as a heading.
- In step 1 **Files** is marked as the current page. After step 3 the app is on `/photos` and **Photos** is marked.
- Tapping the row for the current page closes the drawer and stays on the page.

**Notes:**

- The order is the same on a phone and on a desktop window.
- Left-handed mode moves the drawer to the right edge (JN-ST-033). The rows, the heading and their order do not
  change.

---

### JN-NV-002: The drawer hides what an account cannot open

**Preconditions:** Logged in as a member who is not an admin. An admin has turned the Calendar, Slides and Chat
betas off (JN-ST-028).

**Steps:**

1. Open the drawer.
2. Read the rows from top to bottom.

**Expected result:**

- The everyday pages are **Files**, **Photos**, **Docs**, **Sheets**, **Books**. There is no **Calendar**, **Slides**
  or **Chat** row, and no **Vault** row (JN-VT-000).
- The **Manage** heading is still there, with **Trash**, **System** and **Settings** under it. There is no **Users**
  row (JN-USR-002).

**Notes:**

- A row appears or disappears without a reload when an admin turns a beta on or off, or changes the account's admin
  role (JN-USR-003, JN-USR-004).
- Hiding a row decides what the drawer shows and nothing more. Opening a hidden page by its address is refused
  separately.
