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
| `Presentation`   | `title`, `size` (a `SlideSize`), `theme` reference, `slides`           |
| `Slide`          | stable `id`, `background`, `elements` back to front, speaker `notes`   |
| `SlideElement`   | sealed: `TextBox`, `ShapeElement`, `ImageElement`, `LineElement`, `UnknownElement` |
| `ElementFrame`   | `x`, `y`, `width`, `height` in slide units, `rotation` in degrees       |
| `TextBox`        | paragraphs, vertical `anchor`, `autoFit` (grow, fixed, shrink), `placeholder` |
| `TextParagraph`  | styled `TextRun`s, alignment, `lineSpacing`, `list` (none, bullet, numbered) |
| `TextRun`        | text with bold, italic, underline, strikethrough, size, family, color  |
| `ShapeElement`   | `kind`, solid `fill` or none, `stroke`, `cornerRadius`, `opacity`      |
| `LineElement`    | `stroke`, `flipped`, `startCap` and `endCap` (none or arrow), `opacity` |
| `ImageElement`   | `source` (an `ImageSource` reference), `altText`, `fit`                |
| `Stroke`         | `color`, `width`, `dash` (solid, dash, dot, dash-dot)                  |

Slide units are an abstract space set by `SlideSize` (1920×1080 for the
default 16:9). Stacking order is an element's index in `Slide.elements`. Ids are
unique across the whole presentation and never change for the life of a slide
or element.

## The `.qslide` format

A presentation is saved as a file, as sheets (`.qsheet`) and documents
(`.qdoc`) are, not as database rows. A `.qslide` file is UTF-8 JSON:

```json
{
  "schemaVersion": 1,
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
enum (paragraph alignment, image fit, line cap) reads as its default.

## Editing and undo

`SlideDocumentController` applies commands and keeps a 100-step undo
history of earlier presentations:

- slides: `addSlide`, `duplicateSlide`, `deleteSlide`, `moveSlide`, `setSlideNotes`
- elements: `addElement`, `moveElements`, `resizeElement`, `rotateElement`,
  `deleteElements`, `reorderElement`, `arrangeElements`
- text: `editText`, `formatText` (a `TextFormat` over whole boxes),
  `insertTextBox(slideId, at: (x: 160, y: 120))`
- drawing: `insertShape`, `insertLine`, `insertImage`, `styleElements` (an
  `ElementStyle` over shapes and lines), `setAltText`
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
It depends on nothing but Flutter: colors come from the ambient
`ColorScheme`, or from a `SlideCanvasStyle` the app fills with its own
tokens, and pictures come from an `imageBuilder` the app supplies, since the
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

SlideCanvas.readOnly(slide: slide, size: deck.size); // thumbnails, presenting
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

## Development

```sh
make -C packages/quark_slides check
make -C packages/quark_slides test
```
