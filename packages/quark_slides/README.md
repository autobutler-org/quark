# quark_slides

A headless presentation engine: the immutable slide model, the `.qslide` file
format, and a document controller with undo. It draws nothing; a slide editor
or viewer is built on top of it.

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
  `deleteElements`, `reorderElement`, `editText`
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

## Development

```sh
make -C packages/quark_slides check
make -C packages/quark_slides test
```
