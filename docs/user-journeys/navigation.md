# Navigation Journeys

Covers the navigation drawer every top-level page opens from its brand button: which destinations it lists, in what
order, and which ones a given account sees.

---

### JN-NV-001: The drawer leads with the household's pages

**Preconditions:** Logged in as an admin. Calendar, Chat, and Slides are always listed.

**Steps:**

1. On Files, tap the brand button to open the drawer.
2. Read the rows from top to bottom, scrolling if the screen is shorter than the list.
3. Tap **Photos**, then open the drawer again.

**Expected result:**

- Under the header that names the Quark, the everyday pages come first, in this order: **Files**, **Photos**,
  **Music**, **Calendar**, **Docs**, **Sheets**, **Slides**, **Books**, **Chat**, **Vault**.
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

**Preconditions:** Logged in as a member who is not an admin.

**Steps:**

1. Open the drawer.
2. Read the rows from top to bottom.

**Expected result:**

- The everyday pages are **Files**, **Photos**, **Music**, **Calendar**, **Docs**, **Sheets**, **Slides**, **Books**, **Chat**,
  **Vault**. **Vault** opens the account's own vault (JN-VT-000).
- The **Manage** heading is still there, with **Trash**, **System** and **Settings** under it. There is no **Users**
  row (JN-USR-002).

**Notes:**

- A row for a feature still in beta appears or disappears without a reload when an admin turns that beta on or off.
  Slides, Calendar, and Chat stay listed. Changing the account's admin role shows or hides **Users**
  (JN-USR-003, JN-USR-004).
- Hiding a row decides what the drawer shows and nothing more. Opening a hidden page by its address is refused
  separately.
