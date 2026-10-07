# Slides Keyboard Shortcuts

Press `?` or F1 in the slide editor to see this list in the app.

`lib/utils/slide_shortcuts.dart` is the single source of truth: the help dialog
renders it, this page documents it, and `test/utils/slide_shortcuts_test.dart`
fails when a shortcut's name is missing here. Add a shortcut to the code that
handles it, to that table, and to this page together.

**Mod** is Cmd on macOS and iOS, Ctrl everywhere else. Only shortcuts that exist
are listed; save and present-from-the-editor keys
from the original wish list (#1168) are not implemented yet.

---

## Editing

Live on the canvas when no text box is open.

| Keys                       | Action                       |
| -------------------------- | ---------------------------- |
| Mod+Z                      | Undo                         |
| Mod+Shift+Z, Ctrl+Y        | Redo (Cmd+Shift+Z only on a Mac) |
| Delete / Backspace         | Delete the selection         |
| Arrow keys                 | Nudge the selection 1 unit   |
| Shift+Arrow keys           | Nudge the selection 10 units |
| Mod+C                      | Copy the selection           |
| Mod+X                      | Cut the selection            |
| Mod+V                      | Paste                        |
| Mod+D                      | Duplicate the selection      |
| Enter / F2                 | Edit the selected text box   |

## Selection

| Keys      | Action                      |
| --------- | --------------------------- |
| Tab       | Select the next element     |
| Shift+Tab | Select the previous element |
| Esc       | Clear the selection         |

## Text

Live while a text box is being edited.

| Keys                 | Action                       |
| -------------------- | ---------------------------- |
| Esc                  | Finish editing the text box  |
| Mod+B                | Bold                         |
| Mod+I                | Italic                       |
| Mod+U                | Underline                    |
| Mod+A                | Select all text in the box   |
| Mod+Z                | Undo typing                  |
| Mod+Shift+Z, Mod+Y   | Redo typing                  |

## Arrange

| Keys          | Action        |
| ------------- | ------------- |
| Mod+]         | Bring forward |
| Mod+[         | Send backward |
| Mod+Shift+]   | Bring to front |
| Mod+Shift+[   | Send to back  |
| Mod+G         | Group the selection |
| Mod+Shift+G   | Ungroup the selection |

## View

| Keys    | Action                    |
| ------- | ------------------------- |
| ? / F1  | Show keyboard shortcuts   |

## Present

Live while a presentation is running. Keys held with Ctrl, Cmd or Alt are left
to the browser and the system.

| Keys                                   | Action            |
| -------------------------------------- | ----------------- |
| → / Space / Page Down / Enter          | Next slide        |
| ← / Page Up / Backspace                | Previous slide    |
| Home                                   | First slide       |
| End                                    | Last slide        |
| F                                      | Toggle fullscreen |
| Esc                                    | End the show      |

Zoom is by pointer, not keyboard: Ctrl-scroll or a pinch.
