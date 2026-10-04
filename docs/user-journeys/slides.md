# Slides Journeys

Covers the Slides page (`/slides`) and the slide editor for `.qslide` presentations (#1152, #1161).

---

### JN-SL-001: Browse presentations

**Preconditions:** User is logged in.

**Steps:**

1. Open the drawer and tap **Slides**, or navigate to `/slides`.

**Expected result:**

- Every `.qslide` file the user can reach is listed, newest first.
- With none, an empty state reads "No presentations yet" with a **Create a presentation** button.
- The app bar's refresh button, beside the brand button, fetches the list again.

---

### JN-SL-002: Search presentations

**Preconditions:** At least one presentation exists.

**Steps:**

1. Navigate to `/slides`.
2. Type part of a presentation's name, or a word from one of its slides or speaker notes, into the search field.

**Expected result:**

- Presentations whose name matches are listed at once.
- After a pause, presentations whose text matches are listed under **Content matches**, with a snippet.
- With nothing matching, the empty state offers **Create a new presentation instead**.

---

### JN-SL-003: Create a presentation

**Preconditions:** User is logged in.

**Steps:**

1. Navigate to `/slides`.
2. Tap **New presentation** in the top bar (or the empty state's create button).
3. Enter a name and tap **Create**.

**Expected result:**

- A `<name>.qslide` file is created — at the root for an admin, in the member's home folder otherwise.
- The editor opens on it at `/slides/<path>`, with one 16:9 title slide showing the name.

---

### JN-SL-004: Open a presentation

**Preconditions:** A presentation exists.

**Steps:**

1. Tap it in the Slides list, in a search result, or in Files.

**Expected result:**

- The slide editor opens at `/slides/<path>` (with `?serial=<device>` for a file on another drive).
- The slide panel lists every slide as a numbered thumbnail; the first is selected and shown in the middle.
- On a phone the panel is a strip across the top; on a wide window it runs down the left.

---

### JN-SL-005: Deep-link to a presentation, signed out

**Preconditions:** User is signed out. A presentation exists at `talks/pitch.qslide`.

**Steps:**

1. Navigate directly to `/slides/talks/pitch.qslide`.
2. Sign in.

**Expected result:**

- The sign-in page opens with the link kept (`/login?from=...`).
- After signing in, the editor opens on `talks/pitch.qslide`.

---

### JN-SL-006: Add, duplicate and delete slides

**Preconditions:** A presentation is open (JN-SL-004).

**Steps:**

1. Tap **+** (New slide) in the slide panel.
2. Open a slide's **⋮** menu (or right-click its thumbnail) and choose **Duplicate**.
3. Open a slide's menu and choose **Delete**.

**Expected result:**

- A new blank slide appears after the selected one and is selected, scrolled into view.
- The duplicate appears right after its original and is selected.
- The deleted slide is gone and the slide that took its place is selected.
- **Delete** is disabled while only one slide is left.

---

### JN-SL-007: Reorder slides

**Preconditions:** A presentation with at least two slides is open.

**Steps:**

1. Drag a thumbnail to a new place in the panel (a long press first on a touch screen).
2. Or open a slide's menu and choose **Move earlier** or **Move later**.

**Expected result:**

- The slide moves and the thumbnails renumber.
- **Move earlier** is disabled on the first slide and **Move later** on the last.

---

### JN-SL-008: Undo and redo

**Preconditions:** A presentation is open and a slide was added, duplicated, deleted or moved.

**Steps:**

1. Tap **Undo** in the top bar.
2. Tap **Redo**.

**Expected result:**

- Undo takes the last change back; redo puts it back.
- Each button is disabled when there is nothing to undo or redo.

---

### JN-SL-009: Autosave

**Preconditions:** A presentation is open.

**Steps:**

1. Change the presentation (JN-SL-006 or JN-SL-007).
2. Wait two seconds.

**Expected result:**

- The save chip reads **Save** while changes wait, **Saving…** while they are sent, then **Saved**.
- Tapping **Save** saves at once.
- Leaving the editor before the pause is over still saves the change.
- Reopening the presentation shows the saved slides.

---

### JN-SL-010: Save fails

**Preconditions:** A presentation is open. The Quark becomes unreachable or refuses the write.

**Steps:**

1. Change the presentation and wait for the autosave.

**Expected result:**

- A snack bar reads "Couldn't save the presentation." (or the Quark's own reason).
- The save chip reads **Retry save**; the changes stay on screen.
- Tapping **Retry save** once the Quark is back saves them.

**Notes:** The slide editing canvas itself (#1153) lands separately; until then the middle of the editor shows the selected slide read-only.
