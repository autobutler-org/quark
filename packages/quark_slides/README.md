# quark_slides

A presentation engine: the immutable slide model, the `.qslide` file format, a
document controller with undo, and a canvas that draws a slide and edits it
through that controller. An app builds its editor and viewer around them.

It is the core of the Slides epic (#1152) and, like the other packages here,
depends on nothing in the Quark app.

## Model

Everything is immutable and compares by value. An edit makes a new
`Presentation`, which shares every slide and element it did not touch.

| Type             | What it holds                                                          |
| ---------------- | ---------------------------------------------------------------------- |
| `Presentation`   | `title`, `size` (a `SlideSize`), `theme` (a `SlideTheme` or none), `slides` |
| `Slide`          | stable `id`, `background`, `elements` back to front, speaker `notes`, `layoutId` |
| `SlideElement`   | sealed: `TextBox`, `ShapeElement`, `ImageElement`, `LineElement`, `GroupElement`, `UnknownElement` |
| `ElementFrame`   | `x`, `y`, `width`, `height` in slide units, `rotation` in degrees       |
| `TextBox`        | paragraphs, vertical `anchor`, `autoFit` (grow, fixed, shrink), `placeholder`, layout `slot`, `textRole` |
| `TextParagraph`  | styled `TextRun`s, alignment, `lineSpacing`, `list` (none, bullet, numbered) |
| `TextRun`        | text with bold, italic, underline, strikethrough, size, family, color  |
| `ShapeElement`   | `kind`, solid `fill` or none, `stroke`, `cornerRadius`, `opacity`      |
| `LineElement`    | `stroke`, `flipped`, `startCap` and `endCap` (none or arrow), `opacity` |
| `ImageElement`   | `source` (an `ImageSource` reference), `altText`, `fit`                |
| `GroupElement`   | `children`, back to front, in group-local frames; groups nest          |
| `Stroke`         | `color`, `width`, `dash` (solid, dash, dot, dash-dot)                  |
| `SlideColor`     | a literal 32-bit color value, or a theme role: `SlideColor.theme(ThemeColor.accent1)` |

Slide units are an abstract space set by `SlideSize` (1920×1080 for the
default 16:9). Stacking order is an element's index in `Slide.elements`. Ids are
unique across the whole presentation and never change for the life of a slide
or element.

## The `.qslide` format

A presentation is saved as a file, as sheets (`.qsheet`) and documents
(`.qdoc`) are, not as database rows. A `.qslide` file is UTF-8 JSON:

```json
{
  "schemaVersion": 2,
  "title": "Demo",
  "size": { "width": 1920, "height": 1080 },
  "slides": [
    {
      "id": "s1",
      "elements": [
        {
          "id": "e1",
          "type": "shape",
          "kind": "ellipse",
          "frame": { "x": 100, "y": 80, "width": 400, "height": 300 },
          "fill": "#3366FF"
        }
      ]
    }
  ]
}
```

`test/fixtures/sample.qslide` is a golden file that uses every field.

```dart
final deck = QslideCodec.decode(text);
final saved = QslideCodec.encode(deck);
```

**Versioning.** An additive change keeps `schemaVersion`. Every object keeps
the fields it does not recognize in `extra` and writes them back, and an
element of an unknown `type` (or a shape of an unknown `kind`) is kept
verbatim as an `UnknownElement`, so an older reader can open, edit and save a
newer file without losing anything. A breaking change bumps `schemaVersion`,
and a reader refuses a file newer than `QslideCodec.schemaVersion` with a
`QslideFormatException` rather than misreading it. An unknown value of a small
enum (paragraph alignment, image fit, line cap, text role, theme color
role) reads as its default.

**Migration.** A file older than `QslideCodec.schemaVersion` is upgraded one
version at a time as it is read, and saved at the current version. Version 2
added the inline theme, role colors (`"fill": "theme:accent1"`), slide
`layout`s and text box `slot`s and `textRole`s. A version 1 file's `theme`
was a reference string nothing drew; it becomes the built-in theme with that
id, or none, and every slide reads as blank-layout.
`test/fixtures/v1_sample.qslide` is the golden version 1 file.

## Themes and layouts — for a theme or layout picker

A `SlideTheme` is a palette of ten `ThemeColor` roles (`background`,
`text`, `background2`, `text2`, `accent1` to `accent6`), a heading and a
body font, a `ThemeTextStyle` (size, color, heading or body font) for each
`ThemeTextRole` — `title`, `subtitle`, `body` — and the `ThemeShapeStyle`
new shapes and lines get. It is stored in the `.qslide` file, so a custom
theme needs no server. Elements refer to it rather than copy it: a color
can be a role, and a text run's unset size, family and color come from the
theme's style for its box's `textRole`. Changing the theme restyles the
whole deck in one step; literal colors and a run's own size stay put.

```dart
SlideThemes.all; // light, dark, warm, cool, highContrast: a picker's cards
doc.controller.setTheme(SlideThemes.dark); // one undo step; null for none
final ours = SlideThemes.cool.copyWith(
  id: 'ours',
  name: 'Ours',
  colors: SlideThemes.cool.colors.copyWith({ThemeColor.accent1: 0xFF0A7E8C}),
  headingFont: 'Lora',
);
const accent = SlideColor.theme(ThemeColor.accent1);
accent.resolve(deck.theme); // the color value to paint; a literal ignores the theme
```

A swatch for a role is `Color(theme.colors[role])`. A role color's literal value
is its light-theme fallback; paint with `resolve`.

A `SlideLayout` is a set of `LayoutPlaceholder` slots, each a text role, a
prompt and a box in fractions of the slide. `SlideMaster.standard` holds the
built-in five — `title`, `titleAndContent`, `sectionHeader`, `twoContent`
and `blank` — and a slide names its own by `layoutId`. A placeholder is a
`TextBox` whose `slot` names its slot; it inherits the slot's frame, anchor
and alignment until the user changes them, and the theme's text style until
a run sets its own.

| Command | Does |
| --- | --- |
| `insertSlideWithLayout(layoutId, index:)` | a slide with an empty placeholder per slot; returns its id |
| `setSlideLayout(slideId, layoutId)` | fills the new slots by slot, then role, keeping typed text; untouched placeholders re-flow, moved ones stay; leftover text becomes an ordinary box, leftover empty placeholders go |
| `resetSlideToLayout(slideId)` | puts placeholders back where the layout has them, drops their runs' own size, family and color, and restores deleted ones |
| `setTheme(theme)` | swaps the theme; growing text boxes refit to its sizes |

Each is one undo step, and an unknown layout id throws an `ArgumentError`.
The pure functions underneath — `layoutBoxes`, `applyLayout`,
`resetToLayout` — are exported and tested on their own. New shapes and lines
take `controller.shapeStyle`: the theme's, or the light theme's when the
deck has none.

**Drawing.** The canvas resolves every role and unset text style against
the deck's theme as it paints; `SlideCanvas.readOnly` takes a `theme` for
thumbnails and presenting. A deck with no theme is drawn in
`slideFallbackTheme(style, colorScheme)`: the canvas style's slide and text
colors with the app's `ColorScheme` accents, so it matches the app around
it. A placeholder reads to a screen reader with its role first: "Title:
Quarterly review", or "Subtitle placeholder: Click to add subtitle" while
empty (`ThemeTextRole.label`).

## Editing and undo

`SlideDocumentController` applies commands and keeps a 100-step undo
history of earlier presentations:

- slides: `addSlide`, `duplicateSlide`, `deleteSlide`, `moveSlide`, `setSlideNotes`,
  `setSlideBackground`
- themes and layouts: `setTheme`, `insertSlideWithLayout`, `setSlideLayout`,
  `resetSlideToLayout` (see [Themes and
  layouts](#themes-and-layouts--for-a-theme-or-layout-picker))
- elements: `addElement`, `moveElements`, `resizeElement`, `rotateElement`,
  `deleteElements`, `reorderElement`, `arrangeElements`
- text: `editText`, `formatText` (a `TextFormat` over whole boxes),
  `insertTextBox(slideId, at: (x: 160, y: 120))`
- drawing: `insertShape`, `insertLine`, `insertImage`, `styleElements` (an
  `ElementStyle` over shapes and lines), `setAltText`
- groups and layout: `groupElements`, `ungroupElements`, `alignElements`,
  `distributeElements`, `matchSize` (see [Groups and
  alignment](#groups-and-alignment--for-a-toolbar))
- clipboard: `copyElements`, `pasteElements`, `duplicateElements`,
  `pasteText` (see [Copy and paste](#copy-and-paste))
- find and replace: `replaceCurrent`, `replaceAll` (see [Find and
  replace](#find-and-replace--for-a-find-bar))
- history: `undo`, `redo`, `load`, and `batch` / `beginBatch` / `endBatch`

A command that changes nothing records no step. Commands inside a batch apply
and notify immediately but undo as one step, which is what a multi-element
drag needs:

```dart
final doc = SlideDocumentController(deck);
doc.beginBatch(); // pointer down
doc.moveElements(slideId, selection, dx, dy); // each pointer move
doc.endBatch(); // pointer up: one undo step
```

A text box whose `autoFit` is `grow` grows taller to fit its text in the
same step as any command that changes its text, formatting or size; it never
shrinks on its own. Measuring text needs Flutter, so the controller takes a
`measureText` function; `SlideDocumentNotifier` passes
`SlideTextLayout().measure` by default.

The controller is plain Dart; its `onChanged` callback is the only hook.
`SlideDocumentNotifier` wraps it in a `ChangeNotifier` for Flutter:

```dart
final notifier = SlideDocumentNotifier(deck);
ListenableBuilder(listenable: notifier, builder: ...);
notifier.controller.addSlide();
```

## Canvas

`SlideCanvas` draws a slide and, given a `SlideDocumentNotifier`, edits it.
It depends on nothing but Flutter: slide content is colored by the deck's
theme, and the chrome by the ambient `ColorScheme`, or by a
`SlideCanvasStyle` the app fills with its own tokens, and pictures come from an `imageBuilder` the app supplies, since the
package never loads a file.

```dart
SlideCanvas(
  document: doc,
  slideId: slideId,
  selection: selection,
  onSelectionChanged: (ids) => setState(() => selection = ids),
  zoom: zoom, // 1 fits the box; SlideCanvas.minZoom to maxZoom
  onZoomChanged: (z) => setState(() => zoom = z),
  imageBuilder: (context, image) => Image.network(image.source, fit: image.fit),
);

SlideCanvas.readOnly(slide: slide, size: deck.size, theme: deck.theme);
```

The slide is laid out at its logical size and scaled, so text wraps the
same way at every zoom, and the device text scale does not resize slide
content. Every gesture goes through `SlideDocumentController` and is one
undo step: tap to select (Shift, Ctrl or Cmd to add), marquee on empty
space, drag to move with snapping to the slide's and other elements' edges
and centers (Alt to place freely), eight resize handles and a rotate handle
drawn 12dp wide with 48dp hit areas, arrow keys to nudge (Shift for ten),
Delete, Tab to step through elements, and Ctrl/Cmd `]` and `[` (with Shift:
to front, to back) for stacking order, which `arrangeElements` also offers
to a toolbar. Scroll, middle-drag or two fingers pan; Ctrl-scroll or a pinch
zooms. The canvas does not animate.

Each element's widget is keyed `slide_element_<id>` and reads to a screen
reader through `elementLabel` (`defaultSlideElementLabel` in English); each
handle is keyed `slide_handle_<id>`, `slide_handle_bottom_right` and so on.
The math behind the gestures — `FrameGeometry`, `snapMove`,
`SlideViewport` — is exported and tested on its own.

## Text editing

Text is edited in place on the canvas: double-click or double-tap a text
box, or select one and press Enter or F2. The editor sits on the slide at
the canvas's scale and rotation, wraps lines exactly where the drawn text
does, and gives the platform's caret, selection, input methods, context
menu and touch handles. Escape or a click outside the box ends editing.
Everything typed and formatted in one session is **one undo step** on the
document; Ctrl/Cmd+Z inside the editor steps back through the session
itself. Ctrl/Cmd+B, I and U toggle bold, italic and underline, and
Ctrl/Cmd+A selects every paragraph.

The text tool draws new boxes: `tools.use(SlideCanvasTool.text)` (see
[Drawing tools](#drawing-tools-and-insertion--for-a-toolbar)), and a click
places a box at the default width (a drag sizes it), which opens for typing.
A new box left empty disappears again.

### For a toolbar: `SlideTextEditingController`

Create one, pass it to the canvas, and drive every text command through it.
It formats the editor's selection while a box is being edited and every
selected text box whole otherwise, as one undo step either way:

```dart
final editing = SlideTextEditingController(fontFamilies: ['Inter', 'Lora']);

SlideCanvas(document: doc, slideId: slideId, textEditing: editing, ...);

ListenableBuilder(
  listenable: editing,
  builder: (context, _) {
    final format = editing.selectionFormat; // what the selection shares
    return Row(children: [
      IconButton(
        isSelected: TextToggle.bold.isOn(format),
        onPressed: editing.canFormat
            ? () => editing.toggle(TextToggle.bold)
            : null,
        icon: const Icon(Icons.format_bold),
      ),
      // fontSize is a double when the selection shares one, null when it
      // inherits, and `unset` when it is mixed.
      Text(format.fontSize is double ? '${format.fontSize}' : ''),
    ]);
  },
);

editing.format(const TextFormat(fontSize: 48.0));
editing.format(const TextFormat(alignment: TextAlignment.center));
editing.format(const TextFormat(color: SlideColor(0xFF3366FF)));
editing.format(const TextFormat(fontFamily: 'Lora'));
editing.format(const TextFormat(lineSpacing: 1.5));
editing.format(const TextFormat(anchor: TextAnchor.middle));
editing.format(const TextFormat(autoFit: TextAutoFit.shrink));
editing.toggle(TextToggle.bulletList); // italic, underline, strikethrough,
                                       // numberedList likewise
```

| Member | What it does |
| --- | --- |
| `toggle(TextToggle)` | bold, italic, underline, strikethrough, bullet or numbered list: on unless all of the selection has it |
| `format(TextFormat)` | any mix of run, paragraph and box changes; a field left out is left alone, `null` makes a size, family, color or spacing inherit |
| `selectionFormat` | the `TextFormat` the selection shares; mixed fields are left out |
| `canFormat` | a box is being edited, or a text box is selected |
| `isEditing`, `elementId`, `draft`, `textSelection` | the open session |
| `commit()`, `cancel()` | end the session, writing it as one step or dropping it |
| `fontFamilies` | the families the app offers |

At a collapsed caret a run format styles what is typed next. Call
`editing.commit()` before the document's own undo or redo, so the step the
session makes exists before history moves. The formatting itself is pure
functions over runs — `replaceText`, `formatParagraphs`, `formatTextBox`,
`textFormatOf`, `typingStyleAt`, `listMarkers` — which split and merge runs
and carry unknown fields along; `SlideDocumentController.formatText` applies
a `TextFormat` to whole boxes without a canvas.

**Keys.** While a box is edited, each of its paragraphs is keyed
`slide_text_paragraph_<index>`.

**Accessibility.** A text box reads to a screen reader as its text, or its
placeholder when empty. Editing announces `editingAnnouncement` ("Editing
text") and `editingDoneAnnouncement`; the editor's fields are ordinary text
fields to a screen reader, and a screen reader's tap on a selected text box
opens it. Slide text ignores the device text scale while editing too.

## Shapes, lines and images

A `ShapeElement` is a rectangle, rounded rectangle, ellipse, triangle,
diamond, right arrow (`ShapeKind.arrow`) or star, fitted to its frame. It has
a solid fill or none, an outline with a color, width and dash or none, a
corner radius when it is a rounded rectangle (15% of its shorter side when
unset), and an opacity. A `LineElement` is a line, or an arrow when either
cap is `LineCap.arrow`, with the same stroke and opacity. They are drawn by
`CustomPainter`s over pure path builders — `shapePath`, `starPoints`,
`lineEnds`, `arrowheadPath`, `dashIntervals`, `dashedPath` — which are
exported and tested as geometry.

An `ImageElement`'s `source` is an `ImageSource` written as one string:

| `ImageSource`        | Stored as        | What it is                                  |
| -------------------- | ---------------- | ------------------------------------------- |
| `QuarkFileImage`     | the path itself  | a file in the user's Quark (`photos/a.jpg`) |
| `UploadedAssetImage` | `asset:<id>`     | an asset the app uploaded for the deck      |

`ImageSource.parse(element.source)` (or `SlideImageSource.imageSource` in an
image builder) reads it back. The package never loads a picture: the canvas
asks the app's `imageBuilder`. An image's `altText` is what a screen reader
reads for it ("Image: A dog on a beach"). Resizing an image keeps its aspect
ratio, at an edge handle as well as a corner, unless Alt is held. Cropping is
not supported yet.

## Drawing tools and insertion — for a toolbar

`SlideToolController` holds the active `SlideCanvasTool`. Pass one to the
canvas and to the toolbar; the toolbar calls `use` and listens to light the
active button:

```dart
final tools = SlideToolController();

SlideCanvas(
  document: doc,
  slideId: slideId,
  tools: tools,
  // The image tool marks where a picture goes; the app picks one.
  onPickImage: (box) async {
    final picked = await pickImage(); // the app's picker and upload
    if (picked == null) return;
    final id = doc.controller.insertImage(
      slideId,
      QuarkFileImage(picked.path), // or UploadedAssetImage(assetId)
      (width: picked.width, height: picked.height),
      within: box, // null: centered, within 60% of the slide
      altText: picked.description,
    );
    setState(() => selection = {id});
  },
  ...
);

ListenableBuilder(
  listenable: tools,
  builder: (context, _) => IconButton(
    isSelected: tools.tool == const SlideCanvasTool.shape(ShapeKind.star),
    onPressed: () => tools.use(const SlideCanvasTool.shape(ShapeKind.star)),
    tooltip: defaultSlideToolLabel(const SlideCanvasTool.shape(ShapeKind.star)),
    icon: const Icon(Icons.star_outline),
  ),
);
```

| Tool | Mode | Draws |
| --- | --- | --- |
| `SlideCanvasTool.select` | `select` | nothing: selects and edits |
| `SlideCanvasTool.text` | `text` | a text box, opened for typing |
| `SlideCanvasTool.shape(kind)` | `shape` | a shape of any `ShapeKind` |
| `SlideCanvasTool.line` | `line` | a line |
| `SlideCanvasTool.arrowLine` | `line` | a line with an arrowhead where the drag ends |
| `SlideCanvasTool.image` | `image` | nothing: calls `onPickImage` with the box drawn, or `null` |

With a drawing tool, a click places the element at its default size with
its top-left corner at the pointer, and a drag draws it, previewed as it
goes: Shift keeps a shape square or turns a line in 45° steps, and Alt draws
out from the point pressed. Each insertion is **one undo step**; the canvas
selects the new element (through `onSelectionChanged`) and calls
`tools.reset()`, back to select. Escape does the same without inserting.

**Without a pointer.** A toolbar button activated from the keyboard calls
the document directly; each command centers the element on the slide by
default, returns its id for the toolbar to select, and is one undo step:

```dart
final c = doc.controller;
c.insertShape(slideId, ShapeKind.ellipse);         // 400×400, blue
c.insertLine(slideId, endCap: LineCap.arrow);      // 400 long, horizontal
c.insertTextBox(slideId, at: (x: 660, y: 500));
c.insertImage(slideId, source, (width: w, height: h));
```

With a drawing tool active, Enter on the focused canvas inserts at the
center too, and a screen reader sees the canvas as an action labeled by
`toolLabel` ("Insert star"; `defaultSlideToolLabel` in English) whose tap
inserts.

**Styling.** `styleElements` applies an `ElementStyle` to the shapes and
lines of a selection as one step, skipping other elements; a field left out
is left alone. `elementStyleOf(elements)` summarizes what a selection
shares, for the toolbar's controls:

```dart
c.styleElements(slideId, selection, const ElementStyle(fill: null)); // hollow
c.styleElements(slideId, selection, const ElementStyle(
  strokeColor: SlideColor(0xFF000000),
  strokeWidth: 4,
  dash: StrokeDash.dash,
));
c.styleElements(slideId, selection, const ElementStyle(opacity: 0.5));
c.styleElements(slideId, selection, const ElementStyle(cornerRadius: 24.0));
c.styleElements(slideId, selection, const ElementStyle(endCap: LineCap.arrow));
c.setAltText(slideId, imageId, 'A dog on a beach');
```

**Keys.** The element being drawn is previewed under the key
`slide_element_` (an empty id) and is hidden from screen readers; the new
element is `slide_element_<id>` like any other.

## Groups and alignment — for a toolbar

A `GroupElement` holds its `children` in **group-local** frames: measured
from the group frame's top-left corner along its own axes, before its
rotation. Moving or rotating a group leaves them alone; resizing it scales
them (`resizeGroup`). The group's frame is kept to its children's bounds,
so editing a child refits it (`fitGroup`). In `.qslide` a group is
`{"type": "group", "children": [...]}`; a reader that predates groups
keeps one verbatim as an `UnknownElement`, and an unknown child inside a
group survives the same way.

On the canvas a group selects, moves, resizes and rotates as one element.
Double-click or double-tap it — or press Enter — to enter it and select
the child under the pointer; its outline stays drawn faintly. Escape, or a
press outside it, steps back out. Ctrl/Cmd+G groups the selection and
Ctrl/Cmd+Shift+G ungroups it.

Every element command — move, resize, rotate, delete, restack, style,
text — reaches grouped elements too, by id. Coordinates a command takes
are on the slide (`slide.frameOnSlide(id)`), whatever groups an element
sits in. `SlideTree` (`allElements`, `findElement`, `ancestorsOf`,
`parentOf`, `frameOnSlide`) sees through groups; `Slide.elementById` sees
only the top level.

A toolbar calls the document directly. Each call is **one undo step**:

```dart
final c = doc.controller;

if (c.canGroup(slideId, selection)) {
  final group = c.groupElements(slideId, selection); // returns the group's id
  setState(() => selection = {group});
}
if (c.canUngroup(slideId, selection)) {
  final freed = c.ungroupElements(slideId, selection); // the children's ids
  setState(() => selection = freed.toSet());
}

// One element aligns to the slide; several to the box around them.
c.alignElements(slideId, selection, ElementAlignment.left);
c.alignElements(slideId, selection, ElementAlignment.middle, toSlide: true);
c.distributeElements(slideId, selection, DistributeAxis.horizontal);
c.matchSize(slideId, selection, SizeMatch.both); // to the largest
c.matchSize(slideId, selection, SizeMatch.width, reference: firstId);
```

| Command | Does | Needs |
| --- | --- | --- |
| `groupElements` | groups in place of the frontmost; nothing moves | `canGroup`: two or more with one parent |
| `ungroupElements` | frees each group's children in its place; nested groups stay | `canUngroup`: a group among them |
| `alignElements` | `left`, `center`, `right`, `top`, `middle`, `bottom`, by rotated bounds | one or more; one aligns to the slide |
| `distributeElements` | equal gaps `horizontal` or `vertical` | three or more; two with `toSlide` |
| `matchSize` | `width`, `height` or `both` of the reference, top-left kept | one or more |

The math is pure and exported — `alignFrames`, `distributeFrames`,
`matchFrameSizes` over `id → ElementFrame` maps, and `groupOf`,
`ungroupChildren`, `resizeGroup`, `fitGroup`, `frameInParent`,
`frameInGroup` and `frameBox` — and tested on its own.

## Copy and paste

Ctrl/Cmd+C, X and V copy, cut and paste the selection on the canvas, and
Ctrl/Cmd+D duplicates it. Copied elements travel as versioned JSON
(`SlideClipboardCodec`: `{"format": "quark-slides/elements", "version":
1, "elements": [...]}`, frames on the slide) through a `SlideClipboard`,
so they paste across slides and presentations. A paste gets fresh ids —
inside groups too — keeps images' sources, lands where the originals were
unless that covers an element exactly, and then moves 16 units right and
down (`SlideDocumentController.pasteOffset`) as many times as it takes, so
pasting or duplicating again lands 16 further on. Plain text from another
app pastes as a new text box. A newer payload version pastes nothing. Each
cut, paste and duplicate is one undo step, and the canvas selects what it
pasted.

The package never touches the platform clipboard. Without one, the canvas
uses `SlideClipboard.memory`, inside the app only; to reach the system
clipboard the app passes its own, as `DataSheetClipboard` does in
`data_table`:

```dart
final clipboard = SlideClipboard(
  read: () async => (await Clipboard.getData('text/plain'))?.text,
  write: (text) => Clipboard.setData(ClipboardData(text: text)),
);

SlideCanvas(document: doc, slideId: slideId, clipboard: clipboard, ...);

// A toolbar's or menu's buttons:
await clipboard.copy(doc.controller, slideId, selection);
await clipboard.cut(doc.controller, slideId, selection);
final pasted = await clipboard.paste(doc.controller, slideId);
setState(() => selection = pasted.toSet());
final copies = doc.controller.duplicateElements(slideId, selection);
```

**Keys.** A group is keyed `slide_element_<id>` like any element, and each
child inside it keeps its own `slide_element_<id>`. A group reads to a
screen reader as `elementLabel` names it ("Group of 2"), with its children
inside.

## Find and replace — for a find bar

`SlideSearch.find` is a pure function over a `Presentation`. It looks
through every text box, inside groups too, and — when the scope asks — each
slide's speaker notes, one paragraph (or notes line) at a time: a match
spans runs of different styles but never a line break, and matches do not
overlap.

```dart
final result = SlideSearch.find(
  doc.presentation,
  const SlideSearchQuery('q3', caseSensitive: false, wholeWord: true),
  scope: SlideSearchScope(slideId: null, includeNotes: true), // all slides
);
result.matches; // SlideMatch, in reading order
final i = result.next(current); // wraps; previous(current) too
doc.controller.replaceCurrent(result.matches[i!], 'Q4'); // one undo step
doc.controller.replaceAll(result.matches, 'Q4');          // one undo step
```

| `SlideMatch` field | What it is |
| --- | --- |
| `slideId`, `slideIndex` | the slide |
| `field` | `SlideMatchField.text` or `.notes` |
| `elementPath` | ids from the outermost group down to the text box; empty for notes |
| `paragraph`, `start`, `end` | the paragraph (or notes line) and UTF-16 offsets in its plain text |
| `text` | what matched, so a replace skips a match the document has moved past |

Reading order is slide order, then the slide's text boxes back to front (a
group's children in its place), then the notes. **Regular expressions**
are off by default; with `regex: true` the query runs in Dart's Unicode
mode. A pattern that does not parse, or that repeats a repeating group
(`(a+)+`) and could backtrack for exponential time, comes back as a
`SlideSearchError` instead of running, and one search stops at
`SlideSearch.maxMatches` or after `SlideSearch.timeBudget`, marking the
result `truncated`. Whole word treats letters and digits of every script
as word characters.

**Replacing.** The replacement takes the formatting of the run holding the
match's first character; runs are split at the match's edges and merged
with same-styled neighbors (`replaceInParagraphs`, `replaceInNotes`). A
placeholder keeps its slot, role and prompt, and a growing box refits.

**On the canvas.** Pass the matches as `highlights` and the one the bar is
on as `currentHighlight`. The canvas paints them behind their text, laid
out exactly as the paragraph is, in `SlideCanvasStyle.highlightColor` and
`currentHighlightColor`; each time `currentHighlight` changes to a text box
on the slide it enters the box's group, selects it and pans to center it.
The app moves to the match's slide itself.

## Development

```sh
make -C packages/quark_slides check
make -C packages/quark_slides test
```
