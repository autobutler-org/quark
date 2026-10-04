# Slides Journeys

Covers the Slides page (`/slides`), the slide editor for `.qslide` presentations, its toolbar and properties panel,
inserting pictures, its speaker notes, and presenting (#1152, #1153, #1158, #1161, #1165, #1166, #1167).

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
- The slide panel lists every slide as a numbered thumbnail; the first is selected, outlined, and open on the canvas in
  the middle.
- The bar's second row reads "Slide 1 of N".
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

**Preconditions:** A presentation is open and a slide was added, duplicated, deleted or moved, or an element was edited
on the canvas (JN-SL-011).

**Steps:**

1. Tap **Undo** in the top bar, or press Ctrl+Z (Cmd+Z on a Mac).
2. Tap **Redo**, or press Ctrl+Shift+Z (Cmd+Shift+Z), or Ctrl+Y.

**Expected result:**

- Undo takes the last change back; redo puts it back, whether it was made in the slide panel or on the canvas.
- A whole drag, resize or rotate undoes as one step.
- Each button is disabled when there is nothing to undo or redo.
- The keys work with focus on the canvas or in the slide panel.

---

### JN-SL-009: Autosave

**Preconditions:** A presentation is open.

**Steps:**

1. Change the presentation (JN-SL-006, JN-SL-007 or JN-SL-011).
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

---

### JN-SL-011: Edit elements on the canvas

**Preconditions:** A presentation with elements on its slides is open.

**Steps:**

1. Tap or click an element on the canvas; Shift-, Ctrl- or Cmd-click another to add it, or drag a box on empty slide.
2. Drag the selection to move it; drag a handle to resize, or the rotate handle to rotate.
3. Press the arrow keys (Shift for ten units), Delete, Tab, or Ctrl/Cmd `]` and `[`.

**Expected result:**

- Selected elements are outlined; one selected element shows eight resize handles and a rotate handle.
- A moved element snaps to the slide's and other elements' edges and centers, with guide lines; Alt places it freely.
- The arrow keys nudge, Delete removes, Tab steps through the elements, and `]` / `[` bring forward and send backward.
- The slide's thumbnail in the panel shows each change, and the save chip reads **Save** until the autosave runs.
- Showing another slide clears the selection.

---

### JN-SL-012: Zoom the canvas

**Preconditions:** A presentation is open.

**Steps:**

1. On a wide window, tap **Zoom in** or **Zoom out** in the bar's second row; on a phone, open **Format** › **Zoom**.
2. Or pinch, or Ctrl/Cmd-scroll, over the canvas; scroll or two-finger drag to pan.
3. Tap the percentage chip (**Fit slide** in the phone menu).

**Expected result:**

- The zoom steps between 50% and 200% of the fitted slide, and the chip shows the current percentage.
- **Zoom in** is disabled at 200% and **Zoom out** at 50%.
- The percentage chip fits the whole slide in the canvas again.
- Zooming is not an edit: it does not mark the presentation unsaved.

---

### JN-SL-013: Pictures on slides

**Preconditions:** A presentation is open whose slides have image elements or background images, named by a path on the
same drive as the presentation (`photos/cover.jpg`).

**Steps:**

1. Open the presentation and look at the canvas and the slide panel.

**Expected result:**

- Each picture loads from the Quark with the user's session, on the canvas and in the thumbnails.
- A muted box stands in while it loads.
- A picture that cannot be loaded — moved, deleted, or the Quark unreachable — shows a muted box with a broken-picture
  icon, and the rest of the slide still draws.

---

### JN-SL-014: Step through slides from the keyboard

**Preconditions:** A presentation with at least two slides is open.

**Steps:**

1. Tap a thumbnail in the slide panel.
2. Press the down (or right) arrow, then the up (or left) arrow.

**Expected result:**

- Each arrow selects the next or previous slide, outlines its thumbnail, scrolls it into view, and opens it on the
  canvas; the first and last slides stop there.
- The arrows move slides, not elements, until the canvas is tapped again.

---

### JN-SL-015: Speaker notes

**Preconditions:** A presentation is open (JN-SL-004).

**Steps:**

1. Tap **Speaker notes** under the canvas.
2. Type into the field, and pause.
3. Show another slide, then come back; tap **Undo**.

**Expected result:**

- The panel opens under the canvas with a multi-line field holding the selected slide's notes; tapping the header again
  closes it.
- The save chip reads **Save** while typing, and the notes are autosaved after the pause (JN-SL-009).
- Each slide keeps its own notes; showing another slide shows its notes in the field.
- **Undo** takes back a burst of typing as one step.
- On a phone the field shrinks rather than push the canvas off the screen.

---

### JN-SL-016: Present

**Preconditions:** A presentation with at least two slides is open.

**Steps:**

1. Tap **Present** in the top bar, or open a slide's **⋮** menu and choose **Present from this slide**.
2. Press Right, Space, Page Down or Enter; then Left, Page Up or Backspace; then Home and End.
3. Tap or click the right two thirds of the screen, then the left third; on a touch screen, swipe left and right.
4. Press Escape, or tap **End the presentation** in the control bar.

**Expected result:**

- The presentation fills the window at `/slides/<path>/present` (`?slide=N` from the Nth slide), each slide as large as
  fits, centered on a dark background, starting at the first slide or the one chosen.
- Edits and notes not yet saved are shown, and are saved on the way.
- The keys, taps and swipes step forward and back, and Home and End jump to the first and last slide; the first and last
  slides stop there.
- A control bar reads "Slide N of M" with previous and next; it fades when the pointer rests and comes back when it moves
  or the screen is touched. With a screen reader running it stays.
- Slides cross-fade, unless reduced motion is on.
- Escape or **End the presentation** returns to the editor.

---

### JN-SL-017: Deep-link to a slide in a presentation

**Preconditions:** A presentation with at least three slides exists at `talks/pitch.qslide`.

**Steps:**

1. Navigate directly to `/slides/talks/pitch.qslide/present?slide=3`, signed in or not.

**Expected result:**

- Signed out, the sign-in page keeps the link (as in JN-SL-005) and the show opens after signing in.
- The presentation loads and opens at slide 3; a number past the end opens the last slide.

---

### JN-SL-018: Presenter view

**Preconditions:** A presentation is being presented (JN-SL-016) in a window at least 900 pixels wide.

**Steps:**

1. Tap **Presenter view** in the control bar.
2. Step through the slides.

**Expected result:**

- The slide shows on the left; beside it, the next slide, the time since the show started (`mm:ss`), and the current
  slide's speaker notes, read-only.
- A slide without notes reads "No notes for this slide."; after the last slide the preview reads "End of presentation".
- The control bar sits under the view and stays.
- On a phone there is no **Presenter view** button; the slide shows alone.

---

### JN-SL-019: Fullscreen while presenting

**Preconditions:** A presentation is being presented (JN-SL-016) in a browser, or on Android or iOS.

**Steps:**

1. Press F, or tap **Fullscreen** in the control bar.
2. Press F again, or tap **Exit fullscreen**.

**Expected result:**

- The browser goes fullscreen, or the phone hides its status and navigation bars; the second press returns.
- Ending the presentation leaves fullscreen.
- The desktop apps have no fullscreen button.

---

### JN-SL-020: Draw with the toolbar

**Preconditions:** A presentation is open (JN-SL-004).

**Steps:**

1. On a wide window, tap **Insert text box**, the **Insert shape** menu (rectangle, rounded rectangle, ellipse, triangle,
   diamond, right arrow, star), **Insert line** or **Insert arrow** in the toolbar under the bar. On a phone, open
   **Insert** in the bar's second row and choose the same.
2. Tap or drag on the slide.

**Expected result:**

- The chosen tool is lit; a tap places the element at its default size, a drag draws it.
- The new element is selected, the tool goes back to **Select**, and the insertion undoes as one step.

---

### JN-SL-021: Format the selection

**Preconditions:** A presentation is open with a text box and a shape on the slide.

**Steps:**

1. Select the text box (or start typing in it), then use the formatting row: the font menu, the size stepper, **Bold**,
   **Italic**, **Underline**, **Strikethrough**, **Text color**, the alignments and the list toggles.
2. Select the shape, then use **Fill color**, **Outline color**, **Outline width**, **Outline style**, **Corner radius**
   (a rounded rectangle) and **Opacity**.
3. With anything selected, use **Arrange** (bring to front, forward, backward, to back), **Duplicate** and **Delete**.
4. On a phone, open **Format** in the bar's second row and use the same controls from its submenus.

**Expected result:**

- With nothing selected the row reads "Select something on the slide to format it"; the groups that apply to the
  selection appear, and the toggles show what the selection has.
- A color palette offers the theme's colors, black and white, a none option, and a hex field for any other color
  (`#RRGGBB`); anything else in the field says how to type it.
- Each change is one undo step and marks the presentation unsaved until the autosave runs.

---

### JN-SL-022: Properties panel

**Preconditions:** A presentation is open.

**Steps:**

1. On a wide window, look right of the canvas; tap **Hide properties** / **Show properties** at the end of the tool
   row. On a phone, open **Format** › **Properties**.
2. Select one element and type a new X, Y, Width, Height or Rotation, then press Enter or leave the field.
3. Select a picture and type its **Alt text**.

**Expected result:**

- Without exactly one element selected the panel says to select one.
- Each value is applied once editing ends, as one undo step; dragging on the canvas updates the fields.
- The alt text is what a screen reader reads for the picture on the slide.

---

### JN-SL-023: Insert a picture

**Preconditions:** A presentation is open.

**Steps:**

1. Open the **Insert image** menu in the tool row (**Insert** › **Image** on a phone).
2. Choose **From this device** and pick a picture; or choose **From your Quark**, browse folders (starting in the
   presentation's folder, **Up one folder** to climb) and tap a picture.

**Expected result:**

- A picture from this device uploads into the presentation's folder, under a new name if one is taken, with a progress
  strip over the canvas; it is streamed, never held whole in memory.
- The picture is placed centered at its own shape, scaled to fit within 60% of the slide, selected, as one undo step;
  its size comes from the file's header.
- A failed upload or listing reads "Couldn't add the picture." (or the Quark's reason) and leaves the slide unchanged.


---

### JN-SL-024: Export to PowerPoint

**Preconditions:** A presentation is open (JN-SL-004).

**Steps:**

1. Tap **Export as PowerPoint (.pptx)**, the download button in the editor's bar.
2. Choose where to save it in the save dialog; in a browser it downloads.

**Expected result:**

- Unsaved edits are saved first; if that save fails it says so (JN-SL-010) and nothing is exported.
- The file is named after the presentation (`Talk.qslide` saves as `Talk.pptx`), and the button shows a spinner and
  ignores taps until the export ends.
- It opens in PowerPoint, Keynote, LibreOffice and Google Slides at the presentation's aspect ratio, with its shapes,
  lines and arrows, text and its formatting, pictures, groups, rotation, stacking order, backgrounds and speaker
  notes.
- Pictures are embedded from the files they name. One that is missing, in a folder the user cannot read, or not a
  PNG, JPEG, GIF or BMP is a gray box carrying its alt text, so the slide keeps its layout.
- Exporting changes nothing in the presentation's folder. A failed export reads "Couldn't export the presentation."
