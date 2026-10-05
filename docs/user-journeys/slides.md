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
3. With anything selected, use **Arrange** (bring to front, forward, backward, to back) and **Delete**; aligning,
   grouping and the clipboard are JN-SL-026 and JN-SL-027.
4. On a phone, open **Format** in the bar's second row and use the same controls from its submenus.

**Expected result:**

- With nothing selected the row holds only the clipboard and reads "Select something on the slide to format it"; the
  groups that apply to the selection appear, and the toggles show what the selection has.
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
4. Under **Slide background**, pick a swatch, type a hex color (`#RRGGBB`), or pick **Theme background**.

**Expected result:**

- Without exactly one element selected the panel says to select one.
- The background color fills the slide behind its elements, as one undo
  step; **Theme background** clears it so the slide follows the presentation's theme, keeping any background picture.
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

---

### JN-SL-025: Keyboard shortcuts

**Preconditions:** A presentation is open (JN-SL-004).

**Steps:**

1. Press `?` or F1 anywhere in the editor, or tap **Keyboard shortcuts** (the keyboard button at the end of the tool
   row; **Format** › **Keyboard shortcuts** on a phone).
2. Type in the search box to narrow the list, then tap **Close** or press Esc.

**Expected result:**

- The dialog lists every shortcut by section (editing, selection, text, arrange, view, present), spelled for the
  platform: ⌘ on macOS and iOS, Ctrl elsewhere.
- Searching keeps the shortcuts whose name, section or keys match every word; a search that matches nothing says so.
- `?` typed into a text box or the notes is typed, not taken as a shortcut; F1 still opens the dialog.
- The list scrolls on a phone and at a 2.0 text scale.

---

### JN-SL-026: Align, distribute, match size and group

**Preconditions:** A presentation is open with several elements on a slide.

**Steps:**

1. Select one element and open **Align** in the format row's arrange group (**Format** › **Arrange** › **Align** on a
   phone); pick left, center, right, top, middle or bottom.
2. Select two or more and align them; with three or more, open **Distribute** and space them horizontally or
   vertically; with two or more, open **Match size** and pick **Same width**, **Same height** or **Same size**.
3. With two or more selected, tap **Group**; with a group selected, tap **Ungroup**. Ctrl+G (⌘G) groups and
   Ctrl+Shift+G (⌘⇧G) ungroups on the canvas.

**Expected result:**

- One element lines up with the slide; several line up with the box around them all.
- Distribute leaves the outermost elements where they are and evens the gaps between them; match size takes the
  largest element's size, each element keeping its top-left corner.
- **Distribute**, **Match size**, **Group** and **Ungroup** appear only when the selection allows them.
- Grouping moves nothing and selects the group; ungrouping selects its elements where they were.
- Each command is one undo step and starts the autosave.

---

### JN-SL-027: Copy, cut, paste and duplicate

**Preconditions:** A presentation is open.

**Steps:**

1. Select elements and tap **Copy** or **Cut** in the format row's clipboard group (**Format** › **Clipboard** on a
   phone), or press Ctrl+C / Ctrl+X (⌘C / ⌘X).
2. Show any slide, in this presentation or another, and tap **Paste** or press Ctrl+V (⌘V).
3. Copy text in another app and paste it onto a slide.
4. Select elements and tap **Duplicate** or press Ctrl+D (⌘D).

**Expected result:**

- Copying uses the system clipboard, so elements pasted into another presentation keep their look and pictures; in a
  browser served over plain HTTP, which blocks the clipboard, copy and paste still work inside the app.
- Pasted elements are selected and land where they were copied from, or 16 units right and down when that spot is
  taken, so repeated pastes and duplicates fan out instead of stacking.
- Plain text from elsewhere becomes a new text box in the middle of the slide, one paragraph per line.
- **Paste** is offered with nothing selected; **Copy**, **Cut** and **Duplicate** need a selection.
- Cut, paste and duplicate are one undo step each; copying changes nothing.

---

### JN-SL-028: Import a PowerPoint file

**Preconditions:** Signed in, on `/slides`, with a `.pptx`, `.pptm` or `.ppsx` file on the Quark or on this device.

**Steps:**

1. Tap **Import PowerPoint** in the bar's second row (**Import** on a phone).
2. Tap **From your Quark**, browse to the file and tap it; or tap **From this device** and choose it in the platform's
   picker.
3. If the summary of what was left out appears, read it and tap **Open presentation**.

**Expected result:**

- The picker on the Quark starts in the folder new files land in and lists only folders and PowerPoint files.
- A file from this device is uploaded, streamed, into that folder first, under a numbered name if its own is taken;
  a file that is not a PowerPoint file is refused before it is uploaded.
- "Importing Talk.pptx…" shows with a spinner until the Quark answers. The presentation is written beside the
  PowerPoint file as `Talk.qslide` (or `Talk_(1).qslide` when that is taken) with its pictures in `Talk_media`; the
  PowerPoint file itself is unchanged.
- When anything could not come across — charts, tables, SmartArt, video, animations, unusual shapes — a summary lists
  each kind once with the slides it was on ("Slides 2 and 5", or "Whole presentation"), before the presentation opens.
  Closing it any way opens the presentation.
- The new presentation opens in the editor at its URL (JN-SL-004).
- A damaged or oversized file reads "Quark couldn't read that PowerPoint file. It may be damaged or too large to
  import."; a folder the user cannot write reads "You can't save files in that folder."; anything else reads
  "Couldn't import the presentation." Nothing opens and the page stays as it was.
- Canceling either picker imports nothing.

---

### JN-SL-029: Open a PowerPoint file from Files as a presentation

**Preconditions:** Signed in, on `/files`, with a `.pptx`, `.pptm` or `.ppsx` file in the listing.

**Steps:**

1. Open the file's menu (the three-dot button, or a long press on the row).
2. Tap **Open as presentation**.

**Expected result:**

- The import runs as in JN-SL-028 — progress, then the summary if anything was left out — and the presentation opens
  in the editor on the same drive.
- The entry is offered only on PowerPoint files the Quark can import: not on a legacy `.ppt`, a folder, or a file
  inside an archive.
- Tapping the PowerPoint file itself still opens it in the generic viewer, as before.

---

### JN-SL-030: Choose a theme

**Preconditions:** A presentation is open (JN-SL-004).

**Steps:**

1. Tap **Theme** in the toolbar, or scroll the properties panel to **Theme** (on a phone: **Format** › **Theme**, which
   opens a sheet).
2. Tap one of the previews: Light, Dark, Warm, Cool or High contrast.
3. Undo.

**Expected result:**

- Each preview is the same sample slide drawn in that theme's fonts and colors; the theme in use is outlined and
  checked, and a screen reader hears it as selected.
- Picking one restyles every slide at once — backgrounds, title and body text, and any color picked from the theme's
  colors — as one undo step, and it is autosaved (JN-SL-009). Colors typed as hex or picked from **More colors** stay
  as they are.
- The slide panel's thumbnails and the presentation (JN-SL-016) are drawn in the theme too.
- A presentation made before themes, or one with none, reads **No theme** above the previews with an **Apply a theme**
  button, which applies Light. Until then it opens, edits and saves as before, drawn in the app's colors.

---

### JN-SL-031: Slide layouts

**Preconditions:** A presentation is open (JN-SL-004).

**Steps:**

1. With a slide selected, tap **Layout** in the toolbar, or scroll the properties panel to **Slide layout** (on a phone:
   **Format** › **Slide layout**), and tap one of Title slide, Title and content, Section header, Two content or Blank.
2. Move a title placeholder, then tap **Reset slide to layout**.
3. Tap **+** in the slide panel.
4. Long-press **+**, or tap the chevron beside it, and pick a layout (on a phone, also **Insert** › **New slide**).

**Expected result:**

- The layout in use is outlined and checked. Changing it keeps what was typed: text moves into the matching slots, and
  text with no slot left stays on the slide as an ordinary box. Empty slots read their prompt ("Click to add title").
- Reset puts the placeholders back where the layout has them and returns their text to the theme's style.
- **+** adds a slide after the selected one on the same layout; the menu adds one on the layout picked. Each is one
  undo step.

---

### JN-SL-032: Theme colors in the color controls

**Preconditions:** A presentation is open with a shape or text box selected (JN-SL-021).

**Steps:**

1. Open **Fill color**, **Outline color**, **Text color**, or the properties panel's **Slide background**.
2. Pick a swatch under **Theme colors**, such as Accent 1.
3. Choose another theme (JN-SL-030).

**Expected result:**

- **Theme colors** lists the theme's ten roles — Background, Text, Background 2, Text 2 and Accent 1 to 6 — drawn in
  the current theme, before **More colors** and the hex field.
- A theme color follows the theme: after step 3 the shape or text takes the new theme's Accent 1. The hex field shows
  the color's value in the current theme.
- In a presentation with no theme, the theme colors are the app's own, as the slide is drawn.

