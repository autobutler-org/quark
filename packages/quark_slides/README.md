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
| `TextParagraph`  | styled `TextRun`s and an alignment                                     |

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
  `deleteElements`, `reorderElement`, `arrangeElements`, `editText`
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

## Development

```sh
make -C packages/quark_slides check
make -C packages/quark_slides test
```
