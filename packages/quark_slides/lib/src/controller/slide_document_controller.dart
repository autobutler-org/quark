import 'dart:math';

import '../format/json_fields.dart';
import '../geometry/group_geometry.dart';
import '../geometry/slide_alignment.dart';
import '../geometry/slide_tree.dart';
import '../model/element_frame.dart';
import '../model/element_style.dart';
import '../model/image_source.dart';
import '../model/presentation.dart';
import '../model/rich_text.dart';
import '../model/slide.dart';
import '../model/slide_background.dart';
import '../model/slide_color.dart';
import '../model/slide_element.dart';
import '../model/stroke.dart';
import '../model/text_format.dart';
import '../model/text_paragraph.dart';
import '../model/text_run.dart';

/// Measures how tall, in slide units, a [TextBox]'s text lays out at its
/// frame's width. `SlideDocumentNotifier` supplies one built on Flutter's
/// text layout; this file stays plain Dart.
typedef TextBoxMeasurer = double Function(TextBox box);

/// Edits a [Presentation] through commands, with undo and redo.
///
/// The controller holds the current [presentation] and replaces it on every
/// command; the model is immutable, so undo history is the list of earlier
/// presentations, which share every slide and element the command did not
/// touch. History keeps [maxUndoDepth] steps (100 by default, as the sheets
/// editor does) and drops the oldest beyond that. A command that changes
/// nothing — moving by zero, reordering to the same place — records no
/// step and does not notify.
///
/// Group work that should undo as one step in a batch: a drag that moves
/// several elements over many pointer events, or a paste of many elements.
/// Inside a batch every command still applies and notifies immediately, so
/// the canvas follows the pointer, but only one step is recorded when the
/// outermost batch ends.
///
/// ```dart
/// final doc = SlideDocumentController(Presentation());
/// final slideId = doc.addSlide();
/// doc.batch(() {
///   doc.moveElements(slideId, selection, 10, 0);
///   doc.moveElements(slideId, selection, 10, 0);
/// });
/// doc.undo(); // back to before both moves
/// ```
///
/// A text box whose [TextBox.autoFit] is [TextAutoFit.grow] grows taller
/// to fit its text whenever a command changes its text, its formatting or
/// its size — in the same step — as long as the controller was given a
/// [measureText]. It never shrinks on its own.
///
/// Commands that name a slide or element that does not exist throw an
/// [ArgumentError]; an index out of range throws a [RangeError]. This class
/// has no Flutter dependency; [onChanged] is its only listener hook, and
/// `SlideDocumentNotifier` adapts it to a `ChangeNotifier`.
class SlideDocumentController {
  /// Creates a controller editing [presentation] with an empty history.
  ///
  /// [newId] generates candidate ids for new slides and elements; the
  /// default makes random base-36 strings. Candidates already in use are
  /// skipped. [onChanged] is called after every change to [presentation],
  /// [canUndo] or [canRedo].
  SlideDocumentController(
    Presentation presentation, {
    String Function()? newId,
    this.onChanged,
    this.maxUndoDepth = 100,
    this.measureText,
  })  : _presentation = presentation,
        _generateId = newId ?? _randomId;

  /// Called after every change to [presentation], [canUndo] or [canRedo].
  void Function()? onChanged;

  /// The most undo steps kept.
  final int maxUndoDepth;

  /// Measures text for auto-grow; without one, text boxes keep the size
  /// they are given.
  final TextBoxMeasurer? measureText;

  final String Function() _generateId;
  final List<Presentation> _undoStack = [];
  final List<Presentation> _redoStack = [];
  Presentation _presentation;
  int _batchDepth = 0;
  Presentation? _batchBase;

  /// The presentation as of the last command.
  Presentation get presentation => _presentation;

  /// Whether [undo] would do anything.
  bool get canUndo => _undoStack.isNotEmpty;

  /// Whether [redo] would do anything.
  bool get canRedo => _redoStack.isNotEmpty;

  /// Whether a batch is open.
  bool get isBatching => _batchDepth > 0;

  // ---------------------------------------------------------------------------
  // History
  // ---------------------------------------------------------------------------

  /// Reverts the last step; returns whether there was one to revert.
  /// Throws a [StateError] inside a batch.
  bool undo() => _travel(_undoStack, _redoStack);

  /// Reapplies the last undone step; returns whether there was one.
  /// Throws a [StateError] inside a batch.
  bool redo() => _travel(_redoStack, _undoStack);

  bool _travel(List<Presentation> from, List<Presentation> to) {
    if (isBatching) throw StateError('cannot undo or redo inside a batch');
    if (from.isEmpty) return false;
    to.add(_presentation);
    _presentation = from.removeLast();
    onChanged?.call();
    return true;
  }

  /// Replaces the presentation outright — after opening a file, say — and
  /// clears the history.
  void load(Presentation presentation) {
    if (isBatching) throw StateError('cannot load inside a batch');
    _presentation = presentation;
    _undoStack.clear();
    _redoStack.clear();
    onChanged?.call();
  }

  /// Opens a batch; every command until the matching [endBatch] undoes as
  /// one step. Batches nest; only the outermost one records the step.
  void beginBatch() {
    if (_batchDepth++ == 0) _batchBase = _presentation;
  }

  /// Closes the batch [beginBatch] opened. Throws a [StateError] when none
  /// is open.
  void endBatch() {
    if (_batchDepth == 0) throw StateError('no batch is open');
    if (--_batchDepth > 0) return;
    final base = _batchBase!;
    _batchBase = null;
    if (base != _presentation) {
      _record(base);
      onChanged?.call();
    }
  }

  /// Runs [body] inside a batch and returns its result. The batch is closed
  /// even if [body] throws; what it changed before throwing is kept.
  T batch<T>(T Function() body) {
    beginBatch();
    try {
      return body();
    } finally {
      endBatch();
    }
  }

  void _record(Presentation previous) {
    _undoStack.add(previous);
    if (_undoStack.length > maxUndoDepth) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _commit(Presentation next) {
    if (next == _presentation) return;
    if (!isBatching) _record(_presentation);
    _presentation = next;
    onChanged?.call();
  }

  // ---------------------------------------------------------------------------
  // Ids
  // ---------------------------------------------------------------------------

  /// An id no slide or element in [presentation] uses yet, for building an
  /// element to pass to [addElement].
  String newId() => _freshIds(1).single;

  List<String> _freshIds(int count) {
    final used = {
      for (final slide in _presentation.slides) ...[
        slide.id,
        for (final element in slide.allElements) element.id,
      ],
    };
    final ids = <String>[];
    while (ids.length < count) {
      final id = _generateId();
      if (used.add(id)) ids.add(id);
    }
    return ids;
  }

  /// [elements] with fresh ids for themselves and every element inside
  /// their groups.
  List<SlideElement> _renewIds(List<SlideElement> elements) {
    var count = 0;
    void tally(SlideElement e) {
      count++;
      if (e is GroupElement) e.children.forEach(tally);
    }

    elements.forEach(tally);
    final ids = _freshIds(count).iterator;
    SlideElement renew(SlideElement e) {
      ids.moveNext();
      final id = ids.current;
      return e is GroupElement
          ? e.copyWith(id: id, children: [for (final c in e.children) renew(c)])
          : e.withId(id);
    }

    return [for (final e in elements) renew(e)];
  }

  static final _random = Random();

  static String _randomId() => List.generate(
        10,
        (_) => _random.nextInt(36).toRadixString(36),
      ).join();

  // ---------------------------------------------------------------------------
  // Slides
  // ---------------------------------------------------------------------------

  /// Inserts a blank slide at [index] (at the end by default) and returns
  /// its id.
  String addSlide({int? index, SlideBackground? background}) {
    final slides = _presentation.slides;
    index ??= slides.length;
    RangeError.checkValueInInterval(index, 0, slides.length, 'index');
    final slide = Slide(id: newId(), background: background);
    _commit(_presentation.copyWith(slides: [...slides]..insert(index, slide)));
    return slide.id;
  }

  /// Inserts a copy of the slide [slideId] right after it and returns the
  /// copy's id. The copy and each of its elements, grouped ones included,
  /// get new ids.
  String duplicateSlide(String slideId) {
    final index = _slideIndex(slideId);
    final source = _presentation.slides[index];
    final copy = source.copyWith(
      id: newId(),
      elements: _renewIds(source.elements),
    );
    _commit(
      _presentation.copyWith(
        slides: [..._presentation.slides]..insert(index + 1, copy),
      ),
    );
    return copy.id;
  }

  /// Removes the slide [slideId].
  void deleteSlide(String slideId) {
    final index = _slideIndex(slideId);
    _commit(
      _presentation.copyWith(
        slides: [..._presentation.slides]..removeAt(index),
      ),
    );
  }

  /// Moves the slide [slideId] so that it ends up at [toIndex].
  void moveSlide(String slideId, int toIndex) {
    final slides = [..._presentation.slides];
    RangeError.checkValidIndex(toIndex, slides, 'toIndex');
    final slide = slides.removeAt(_slideIndex(slideId));
    _commit(_presentation.copyWith(slides: slides..insert(toIndex, slide)));
  }

  /// Replaces the speaker notes of the slide [slideId].
  void setSlideNotes(String slideId, String notes) =>
      _updateSlide(slideId, (slide) => slide.copyWith(notes: notes));

  /// Sets the slide [slideId]'s own background, or clears it with `null`
  /// so the slide falls back to the theme's. Setting the background it
  /// already has records no step.
  ///
  /// ```dart
  /// doc.setSlideBackground(slideId, const SlideBackground(color: c));
  /// ```
  void setSlideBackground(String slideId, SlideBackground? background) =>
      _updateSlide(
        slideId,
        (slide) => slide.copyWith(background: background),
      );

  // ---------------------------------------------------------------------------
  // Elements
  // ---------------------------------------------------------------------------

  /// Inserts [element] on the slide [slideId] at stacking position [index]
  /// (in front of everything by default). Its id must not be in use; take
  /// one from [newId].
  void addElement(String slideId, SlideElement element, {int? index}) {
    if (_idInUse(element.id)) {
      throw ArgumentError.value(element.id, 'element.id', 'already in use');
    }
    _updateSlide(slideId, (slide) {
      final elements = [...slide.elements];
      final at = index ?? elements.length;
      RangeError.checkValueInInterval(at, 0, elements.length, 'index');
      return slide.copyWith(elements: elements..insert(at, element));
    });
  }

  bool _idInUse(String id) => _presentation.slides.any(
        (s) => s.id == id || s.allElements.any((e) => e.id == id),
      );

  /// Moves every element in [elementIds] on the slide [slideId] by [dx],
  /// [dy] slide units, as one step.
  ///
  /// Like every element command, this reaches elements inside groups too:
  /// the move is along the slide's axes whatever the group's rotation, and
  /// the group's frame is refitted around its children (see [GroupElement]).
  void moveElements(
    String slideId,
    Iterable<String> elementIds,
    double dx,
    double dy,
  ) =>
      _updateTree(slideId, elementIds, (e, parent) {
        final (x, y) =
            parent == null ? (dx, dy) : rotateVector(dx, dy, -parent.rotation);
        return e.withFrame(e.frame.translate(x, y));
      });

  /// Gives the element [elementId] a new size, and a new top-left corner
  /// when [x] or [y] is given — as dragging a left or top handle needs.
  ///
  /// The values are the element's frame on the slide (see
  /// `SlideTree.frameOnSlide`), so a handle drag on a grouped element works
  /// the same as on any other. Resizing a group scales its children with it
  /// (see [resizeGroup]).
  void resizeElement(
    String slideId,
    String elementId, {
    required double width,
    required double height,
    double? x,
    double? y,
  }) {
    if (width < 0 || height < 0) {
      throw ArgumentError('a size cannot be negative: $width×$height');
    }
    _updateTree(slideId, [elementId], (e, parent) {
      final onSlide = parent == null ? e.frame : frameInParent(parent, e.frame);
      final resized =
          onSlide.copyWith(x: x, y: y, width: width, height: height);
      return _fitted(
        reframe(e, parent == null ? resized : frameInGroup(parent, resized)),
      );
    });
  }

  /// Sets the element [elementId]'s clockwise rotation on the slide, in
  /// degrees; inside a group, the group's own rotation counts toward it.
  void rotateElement(String slideId, String elementId, double degrees) =>
      _updateTree(
        slideId,
        [elementId],
        (e, parent) => e.withFrame(
          e.frame.copyWith(
            rotation: parent == null
                ? degrees
                : normalizedRotation(degrees - parent.rotation),
          ),
        ),
      );

  /// Removes every element in [elementIds] from the slide [slideId], as one
  /// step. A group left with one element dissolves into it; one left with
  /// none goes too.
  void deleteElements(String slideId, Iterable<String> elementIds) {
    final ids = elementIds.toSet();
    _updateSlide(slideId, (slide) {
      _checkIds(slide, ids);
      return slide.copyWith(elements: _removeFrom(slide.elements, ids));
    });
  }

  static List<SlideElement> _removeFrom(
    List<SlideElement> list,
    Set<String> ids,
  ) =>
      [
        for (final e in list)
          if (ids.contains(e.id))
            ...const <SlideElement>[]
          else if (e is GroupElement)
            ...() {
              final children = _removeFrom(e.children, ids);
              if (children.length == e.children.length) return [e];
              final group = e.copyWith(children: children);
              return children.length < 2
                  ? ungroupChildren(group)
                  : [fitGroup(group)];
            }()
          else
            e,
      ];

  /// Moves the element [elementId] to stacking position [toIndex]: 0 sends
  /// it to the back, the last index brings it to the front.
  void reorderElement(String slideId, String elementId, int toIndex) =>
      _updateSlide(slideId, (slide) {
        final elements = [...slide.elements];
        RangeError.checkValidIndex(toIndex, elements, 'toIndex');
        final element = elements.removeAt(_elementIndex(slide, elementId));
        return slide.copyWith(elements: elements..insert(toIndex, element));
      });

  /// Restacks every element in [elementIds] on the slide [slideId] as one
  /// step, keeping their order among themselves: [ZOrderMove.toFront] and
  /// [ZOrderMove.toBack] move them past everything else, and
  /// [ZOrderMove.forward] and [ZOrderMove.backward] each past one
  /// unselected neighbor. Grouped elements restack among their group's
  /// other children.
  void arrangeElements(
    String slideId,
    Iterable<String> elementIds,
    ZOrderMove move,
  ) {
    final ids = elementIds.toSet();
    _updateLists(slideId, ids, (list) {
      final elements = [...list];
      bool picked(int i) => ids.contains(elements[i].id);
      void swap(int i, int j) {
        final e = elements[i];
        elements[i] = elements[j];
        elements[j] = e;
      }

      switch (move) {
        case ZOrderMove.toFront || ZOrderMove.toBack:
          final chosen = elements.where((e) => ids.contains(e.id)).toList();
          final rest = elements.where((e) => !ids.contains(e.id)).toList();
          return move == ZOrderMove.toFront
              ? [...rest, ...chosen]
              : [...chosen, ...rest];
        case ZOrderMove.forward:
          for (var i = elements.length - 2; i >= 0; i--) {
            if (picked(i) && !picked(i + 1)) swap(i, i + 1);
          }
        case ZOrderMove.backward:
          for (var i = 1; i < elements.length; i++) {
            if (picked(i) && !picked(i - 1)) swap(i, i - 1);
          }
      }
      return elements;
    });
  }

  /// Replaces the text of the text box [elementId]. Throws an
  /// [ArgumentError] when the element is not a [TextBox].
  void editText(
    String slideId,
    String elementId,
    List<TextParagraph> paragraphs,
  ) =>
      _updateTree(
        slideId,
        [elementId],
        (e, _) => _fitted(
          _textBox(e).copyWith(paragraphs: List.unmodifiable(paragraphs)),
        ),
      );

  /// Applies [format] to all the text of every text box in [elementIds]
  /// on the slide [slideId], as one step; other elements in [elementIds]
  /// are skipped, so a toolbar can pass a mixed selection. See [TextFormat].
  void formatText(
    String slideId,
    Iterable<String> elementIds,
    TextFormat format,
  ) =>
      _updateTree(
        slideId,
        elementIds,
        (e, _) => e is TextBox ? _fitted(formatTextBox(e, format)) : e,
      );

  /// Inserts a text box on the slide [slideId] with its top-left corner at
  /// the slide point [at] and returns its id.
  ///
  /// ```dart
  /// final id = doc.insertTextBox(slideId, at: (x: 160, y: 120));
  /// ```
  ///
  /// It is [width] wide ([defaultTextBoxWidth] by default) and [height]
  /// tall; left out, the height fits one line of text when the controller
  /// can [measureText], and is [defaultTextBoxHeight] when it cannot. It
  /// holds [paragraphs] (one empty one by default) and goes in front of
  /// everything, or at stacking position [index].
  String insertTextBox(
    String slideId, {
    required ({double x, double y}) at,
    double? width,
    double? height,
    List<TextParagraph> paragraphs = const [TextParagraph([])],
    String placeholder = '',
    int? index,
  }) {
    var box = TextBox(
      id: newId(),
      frame: ElementFrame(
        x: at.x,
        y: at.y,
        width: width ?? defaultTextBoxWidth,
        height: height ?? 0,
      ),
      paragraphs: List.unmodifiable(paragraphs),
      placeholder: placeholder,
    );
    box = _fitted(box);
    if (box.frame.height == 0 && height == null) {
      box = box.withFrame(box.frame.copyWith(height: defaultTextBoxHeight));
    }
    addElement(slideId, box, index: index);
    return box.id;
  }

  /// The width of a text box [insertTextBox] makes when given none.
  static const defaultTextBoxWidth = 600.0;

  /// The height of a text box [insertTextBox] makes when given none and
  /// unable to measure text.
  static const defaultTextBoxHeight = 80.0;

  // ---------------------------------------------------------------------------
  // Shapes, lines and images
  // ---------------------------------------------------------------------------

  /// Inserts a [kind] of shape on the slide [slideId] and returns its id.
  ///
  /// It fills [frame], or — left out — a [defaultShapeSize] square centered
  /// on the slide, which is what a toolbar's keyboard-operable "insert"
  /// wants. It is filled with [fill] ([defaultShapeFill] unless given;
  /// `null` for hollow), outlined with [stroke] (none by default), and goes
  /// in front of everything, or at stacking position [index].
  ///
  /// ```dart
  /// final id = doc.insertShape(slideId, ShapeKind.star);
  /// ```
  String insertShape(
    String slideId,
    ShapeKind kind, {
    ElementFrame? frame,
    SlideColor? fill = defaultShapeFill,
    Stroke? stroke,
    int? index,
  }) {
    final shape = ShapeElement(
      id: newId(),
      frame: frame ?? _centered(defaultShapeSize, defaultShapeSize),
      kind: kind,
      fill: fill,
      stroke: stroke,
    );
    addElement(slideId, shape, index: index);
    return shape.id;
  }

  /// Inserts a line on the slide [slideId] and returns its id; an arrow
  /// when [endCap] or [startCap] is [LineCap.arrow].
  ///
  /// It runs across [frame] (see [LineElement] for [flipped]), or — left
  /// out — horizontally for [defaultLineLength] through the slide's center.
  /// It is drawn with [stroke] (black, [defaultLineWidth] wide unless
  /// given) and goes in front of everything, or at stacking position
  /// [index].
  ///
  /// ```dart
  /// final id = doc.insertLine(slideId, endCap: LineCap.arrow);
  /// ```
  String insertLine(
    String slideId, {
    ElementFrame? frame,
    bool flipped = false,
    LineCap startCap = LineCap.none,
    LineCap endCap = LineCap.none,
    Stroke? stroke,
    int? index,
  }) {
    final line = LineElement(
      id: newId(),
      frame: frame ?? _centered(defaultLineLength, 0),
      flipped: flipped,
      startCap: startCap,
      endCap: endCap,
      stroke: stroke ?? Stroke(width: defaultLineWidth),
    );
    addElement(slideId, line, index: index);
    return line.id;
  }

  /// Inserts the picture [source], whose pixels are [naturalSize], on the
  /// slide [slideId] and returns its id.
  ///
  /// The picture keeps its aspect ratio. Given [within] — the box a user
  /// drew — it is scaled to fit that box and centered in it; otherwise it
  /// is centered on the slide and scaled down, never up, to fit within
  /// [imageFitFraction] (60%) of the slide's width and height. [altText] is
  /// what a screen reader reads for it. It goes in front of everything, or
  /// at stacking position [index]. A [naturalSize] without area throws an
  /// [ArgumentError].
  ///
  /// The package never loads the picture: the app reads its size when it
  /// picks or uploads it, then calls this.
  ///
  /// ```dart
  /// final id = doc.insertImage(
  ///   slideId,
  ///   const QuarkFileImage('photos/dog.jpg'),
  ///   (width: 4032, height: 3024),
  ///   altText: 'A dog on a beach',
  /// );
  /// ```
  String insertImage(
    String slideId,
    ImageSource source,
    ({double width, double height}) naturalSize, {
    ElementFrame? within,
    String altText = '',
    int? index,
  }) {
    final (:width, :height) = naturalSize;
    if (!(width > 0 && height > 0)) {
      throw ArgumentError.value(naturalSize, 'naturalSize', 'has no area');
    }
    final size = _presentation.size;
    final box = within ??
        _centered(
          size.width * imageFitFraction,
          size.height * imageFitFraction,
        );
    var scale = min(box.width / width, box.height / height);
    if (within == null) scale = min(scale, 1);
    final image = ImageElement(
      id: newId(),
      frame: ElementFrame(
        x: box.x + (box.width - width * scale) / 2,
        y: box.y + (box.height - height * scale) / 2,
        width: width * scale,
        height: height * scale,
      ),
      source: source.ref,
      altText: altText,
    );
    addElement(slideId, image, index: index);
    return image.id;
  }

  /// Restyles every shape and line in [elementIds] on the slide [slideId]
  /// as one step; other elements in [elementIds] are skipped, so a toolbar
  /// can pass a mixed selection. See [ElementStyle].
  ///
  /// ```dart
  /// doc.styleElements(slideId, selection, const ElementStyle(fill: null));
  /// ```
  void styleElements(
    String slideId,
    Iterable<String> elementIds,
    ElementStyle style,
  ) =>
      _updateTree(slideId, elementIds, (e, _) => style.applyTo(e));

  /// Sets the image [elementId]'s alt text, which a screen reader reads
  /// for it. Throws an [ArgumentError] when the element is not an
  /// [ImageElement].
  void setAltText(String slideId, String elementId, String altText) =>
      _updateTree(
        slideId,
        [elementId],
        (e, _) => e is ImageElement
            ? e.copyWith(altText: altText)
            : throw ArgumentError.value(
                elementId, 'elementId', 'is not an image'),
      );

  /// The side of the square [insertShape] makes when given no frame.
  static const defaultShapeSize = 400.0;

  /// The fill [insertShape] gives a shape unless told otherwise.
  static const defaultShapeFill = SlideColor(0xFF3366FF);

  /// The length of the line [insertLine] makes when given no frame.
  static const defaultLineLength = 400.0;

  /// The stroke width of the line [insertLine] makes when given none.
  static const defaultLineWidth = 4.0;

  /// The share of the slide's width and height an inserted image fits
  /// within when no box is drawn for it.
  static const imageFitFraction = 0.6;

  /// A [width] by [height] frame centered on the slide.
  ElementFrame _centered(double width, double height) {
    final size = _presentation.size;
    return ElementFrame(
      x: (size.width - width) / 2,
      y: (size.height - height) / 2,
      width: width,
      height: height,
    );
  }

  static TextBox _textBox(SlideElement e) => e is TextBox
      ? e
      : throw ArgumentError.value(e.id, 'elementId', 'is not a text box');

  /// [element] grown to fit its text, when it is a text box that grows and
  /// there is a [measureText].
  T _fitted<T extends SlideElement>(T element) {
    final measure = measureText;
    if (element is! TextBox ||
        element.autoFit != TextAutoFit.grow ||
        measure == null) {
      return element;
    }
    final height = measure(element);
    if (height <= element.frame.height + 1e-6) return element;
    return element.withFrame(element.frame.copyWith(height: height)) as T;
  }

  // ---------------------------------------------------------------------------
  // Grouping
  // ---------------------------------------------------------------------------

  /// Whether [groupElements] can group [elementIds] on the slide [slideId]:
  /// at least two of them, all directly in the same stacking list — on the
  /// slide itself, or in one group.
  bool canGroup(String slideId, Iterable<String> elementIds) {
    final slide = _presentation.slideById(slideId);
    final ids = elementIds.toSet();
    if (slide == null || ids.length < 2) return false;
    final parents = <String?>{};
    for (final id in ids) {
      final up = slide.ancestorsOf(id);
      if (up == null) return false;
      parents.add(up.isEmpty ? null : up.last.id);
    }
    return parents.length == 1;
  }

  /// Whether [ungroupElements] would ungroup anything: one of [elementIds]
  /// on the slide [slideId] is a group.
  bool canUngroup(String slideId, Iterable<String> elementIds) {
    final slide = _presentation.slideById(slideId);
    return slide != null &&
        elementIds.any((id) => slide.findElement(id) is GroupElement);
  }

  /// Groups [elementIds] on the slide [slideId] into one [GroupElement], as
  /// one step, and returns the group's id.
  ///
  /// Nothing moves on the slide: the group's frame is the box around the
  /// elements, which keep their stacking order among themselves, and the
  /// group takes the place of the frontmost of them. Elements already in a
  /// group make a group nested in it. Throws an [ArgumentError] unless
  /// [canGroup] says yes.
  ///
  /// ```dart
  /// final group = doc.groupElements(slideId, selection);
  /// setState(() => selection = {group});
  /// ```
  String groupElements(String slideId, Iterable<String> elementIds) {
    final ids = elementIds.toSet();
    final slide = _slideOf(slideId);
    _checkIds(slide, ids);
    if (!canGroup(slideId, ids)) {
      throw ArgumentError.value(
        ids,
        'elementIds',
        'needs two or more elements sharing one parent',
      );
    }
    final id = newId();
    _updateLists(slideId, ids, (list) {
      final members = [
        for (final e in list)
          if (ids.contains(e.id)) e,
      ];
      final front = list.lastIndexWhere((e) => ids.contains(e.id));
      return [
        for (final e in list)
          if (!ids.contains(e.id)) e,
      ]..insert(front - members.length + 1, groupOf(id, members));
    });
    return id;
  }

  /// Replaces every group among [elementIds] on the slide [slideId] with
  /// its children, as one step, and returns the children's ids, back to
  /// front.
  ///
  /// Nothing moves on the slide: each child's frame is placed through the
  /// group's, rotation included, and the children take the group's place
  /// in the stacking order. A group nested inside stays a group. Ids that
  /// are not groups are left alone.
  List<String> ungroupElements(String slideId, Iterable<String> elementIds) {
    final ids = elementIds.toSet();
    final freed = <String>[];
    _updateLists(slideId, ids, (list) {
      final next = <SlideElement>[];
      for (final e in list) {
        if (e is GroupElement && ids.contains(e.id)) {
          final children = ungroupChildren(e);
          next.addAll(children);
          freed.addAll(children.map((c) => c.id));
        } else {
          next.add(e);
        }
      }
      return next;
    });
    return freed;
  }

  // ---------------------------------------------------------------------------
  // Alignment
  // ---------------------------------------------------------------------------

  /// Lines up [elementIds] on the slide [slideId] by [alignment], as one
  /// step, moving them along the slide's axes (see [alignFrames]).
  ///
  /// They line up on the box around them all, or on the slide when
  /// [toSlide] — which, left out, is the case for a single element, since
  /// one element can only line up with the slide.
  ///
  /// ```dart
  /// doc.alignElements(slideId, selection, ElementAlignment.left);
  /// ```
  void alignElements(
    String slideId,
    Iterable<String> elementIds,
    ElementAlignment alignment, {
    bool? toSlide,
  }) {
    final frames = _framesOnSlide(slideId, elementIds);
    _placeOnSlide(
      slideId,
      alignFrames(
        frames,
        alignment,
        within: (toSlide ?? frames.length == 1) ? _slideBox : null,
      ),
    );
  }

  /// Spaces [elementIds] on the slide [slideId] out along [axis] with equal
  /// gaps, as one step (see [distributeFrames]): between the outermost two
  /// of three or more, or across the slide when [toSlide].
  void distributeElements(
    String slideId,
    Iterable<String> elementIds,
    DistributeAxis axis, {
    bool toSlide = false,
  }) =>
      _placeOnSlide(
        slideId,
        distributeFrames(
          _framesOnSlide(slideId, elementIds),
          axis,
          within: toSlide ? _slideBox : null,
        ),
      );

  /// Gives [elementIds] on the slide [slideId] the width, height or both of
  /// [reference] — the largest of them, left out — each keeping its
  /// top-left corner, as one step (see [matchFrameSizes]). A group scales
  /// its children.
  void matchSize(
    String slideId,
    Iterable<String> elementIds,
    SizeMatch match, {
    String? reference,
  }) =>
      _placeOnSlide(
        slideId,
        matchFrameSizes(
          _framesOnSlide(slideId, elementIds),
          match,
          reference: reference,
        ),
      );

  SlideBox get _slideBox => (
        left: 0,
        top: 0,
        right: _presentation.size.width,
        bottom: _presentation.size.height,
      );

  /// The frames on the slide of [elementIds], by id.
  Map<String, ElementFrame> _framesOnSlide(
    String slideId,
    Iterable<String> elementIds,
  ) {
    final slide = _slideOf(slideId);
    final ids = elementIds.toSet();
    _checkIds(slide, ids);
    return {for (final id in ids) id: slide.frameOnSlide(id)!};
  }

  /// Gives each element in [frames] its frame on the slide, as one step.
  void _placeOnSlide(String slideId, Map<String, ElementFrame> frames) =>
      _updateTree(slideId, frames.keys, (e, parent) {
        final frame = frames[e.id]!;
        return _fitted(
          reframe(e, parent == null ? frame : frameInGroup(parent, frame)),
        );
      });

  // ---------------------------------------------------------------------------
  // Copy and paste
  // ---------------------------------------------------------------------------

  /// How far each paste or duplicate of the same elements onto the same
  /// slide lands from the last, in slide units, right and down.
  static const pasteOffset = 16.0;

  /// The elements [elementIds] on the slide [slideId], back to front, with
  /// their frames on the slide — what copying them puts on a clipboard. An
  /// element inside a group comes out on its own, placed where it shows; one
  /// whose group is also named comes with its group instead.
  List<SlideElement> copyElements(String slideId, Iterable<String> elementIds) {
    final slide = _slideOf(slideId);
    final ids = elementIds.toSet();
    _checkIds(slide, ids);
    return [
      for (final e in slide.allElements)
        if (ids.contains(e.id) &&
            !slide.ancestorsOf(e.id)!.any((g) => ids.contains(g.id)))
          e.withFrame(slide.frameOnSlide(e.id)!),
    ];
  }

  /// Puts copies of [elements] in front of everything on the slide
  /// [slideId], as one step, and returns their ids.
  ///
  /// Every copy — and every element inside a copied group — gets a fresh
  /// id; everything else, an image's source included, is kept. The copies
  /// land where the originals were, unless one would land exactly on an
  /// element already there, as pasting back onto the slide copied from
  /// does; then they all move [pasteOffset] right and down, as many times
  /// as it takes, so each paste lands 16 units past the last.
  ///
  /// ```dart
  /// final ids = doc.pasteElements(slideId, doc.copyElements(from, selection));
  /// ```
  List<String> pasteElements(String slideId, List<SlideElement> elements) {
    final slide = _slideOf(slideId);
    if (elements.isEmpty) return const [];
    final taken = [
      for (final e in slide.allElements) slide.frameOnSlide(e.id)!,
    ];
    bool lands(ElementFrame a, ElementFrame b) =>
        (a.x - b.x).abs() < 1e-6 &&
        (a.y - b.y).abs() < 1e-6 &&
        (a.width - b.width).abs() < 1e-6 &&
        (a.height - b.height).abs() < 1e-6;
    var shift = 0.0;
    while (shift < 1000 * pasteOffset &&
        elements.any(
          (e) => taken.any((t) => lands(e.frame.translate(shift, shift), t)),
        )) {
      shift += pasteOffset;
    }
    final copies = [
      for (final e in _renewIds(elements))
        e.withFrame(e.frame.translate(shift, shift)),
    ];
    _updateSlide(
      slideId,
      (slide) => slide.copyWith(elements: [...slide.elements, ...copies]),
    );
    return [for (final e in copies) e.id];
  }

  /// Pastes a copy of [elementIds] onto the slide [slideId] itself, as one
  /// step, [pasteOffset] past the originals (and past each earlier
  /// duplicate), and returns the copies' ids.
  List<String> duplicateElements(String slideId, Iterable<String> elementIds) =>
      pasteElements(slideId, copyElements(slideId, elementIds));

  /// Puts plain [text] on the slide [slideId] as a new text box, a
  /// paragraph per line, centered at the default width, as one step, and
  /// returns its id; `null` for blank text, which adds nothing. This is how
  /// text copied from another app pastes.
  String? pasteText(String slideId, String text) {
    if (text.trim().isEmpty) return null;
    final lines = text.replaceAll('\r\n', '\n').split('\n');
    final size = _presentation.size;
    return insertTextBox(
      slideId,
      at: (
        x: (size.width - defaultTextBoxWidth) / 2,
        y: (size.height - defaultTextBoxHeight) / 2,
      ),
      paragraphs: [
        for (final line in lines)
          TextParagraph(line.isEmpty ? const [] : [TextRun(line)]),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

  Slide _slideOf(String slideId) => _presentation.slides[_slideIndex(slideId)];

  int _slideIndex(String slideId) {
    final index = _presentation.indexOfSlide(slideId);
    if (index < 0) throw ArgumentError.value(slideId, 'slideId', 'no slide');
    return index;
  }

  static int _elementIndex(Slide slide, String elementId) {
    final index = slide.indexOfElement(elementId);
    if (index < 0) {
      throw ArgumentError.value(elementId, 'elementId', 'not on ${slide.id}');
    }
    return index;
  }

  void _updateSlide(String slideId, Slide Function(Slide) update) {
    final slides = [..._presentation.slides];
    final index = _slideIndex(slideId);
    slides[index] = update(slides[index]);
    _commit(_presentation.copyWith(slides: slides));
  }

  /// Throws an [ArgumentError] unless every id in [ids] is on [slide], at
  /// any depth.
  static void _checkIds(Slide slide, Set<String> ids) {
    if (ids.isEmpty) return;
    final missing = {...ids}..removeAll(slide.allElements.map((e) => e.id));
    if (missing.isNotEmpty) {
      throw ArgumentError.value(
          missing.first, 'elementId', 'not on ${slide.id}');
    }
  }

  /// Replaces every element in [elementIds], at any depth of the slide
  /// [slideId], with what [update] makes of it, as one step, and refits
  /// every group whose children changed. [update] gets the frame on the
  /// slide of the group holding the element, or `null` on the slide itself.
  void _updateTree(
    String slideId,
    Iterable<String> elementIds,
    SlideElement Function(SlideElement element, ElementFrame? parent) update,
  ) {
    final ids = elementIds.toSet();
    _updateSlide(slideId, (slide) {
      _checkIds(slide, ids);
      return slide.copyWith(
        elements: _mapTree(slide.elements, ids, null, update),
      );
    });
  }

  static List<SlideElement> _mapTree(
    List<SlideElement> list,
    Set<String> ids,
    ElementFrame? parent,
    SlideElement Function(SlideElement, ElementFrame?) update,
  ) {
    var changed = false;
    final mapped = [
      for (final e in list)
        () {
          final SlideElement next;
          if (ids.contains(e.id)) {
            next = update(e, parent);
          } else if (e is GroupElement) {
            final children = _mapTree(
              e.children,
              ids,
              parent == null ? e.frame : frameInParent(parent, e.frame),
              update,
            );
            next = identical(children, e.children)
                ? e
                : fitGroup(e.copyWith(children: children));
          } else {
            next = e;
          }
          changed |= next != e;
          return next;
        }(),
    ];
    return changed ? mapped : list;
  }

  /// Rebuilds, as one step, every stacking list on the slide [slideId] —
  /// the slide's own and each group's children — that holds an element in
  /// [ids], with what [update] makes of it.
  void _updateLists(
    String slideId,
    Set<String> ids,
    List<SlideElement> Function(List<SlideElement> list) update,
  ) {
    List<SlideElement> visit(List<SlideElement> list) {
      final inner = [
        for (final e in list)
          if (e is GroupElement)
            () {
              final children = visit(e.children);
              return listEquals(children, e.children)
                  ? e
                  : fitGroup(e.copyWith(children: children));
            }()
          else
            e,
      ];
      return inner.any((e) => ids.contains(e.id)) ? update(inner) : inner;
    }

    _updateSlide(slideId, (slide) {
      _checkIds(slide, ids);
      return slide.copyWith(elements: visit(slide.elements));
    });
  }
}

/// Where [SlideDocumentController.arrangeElements] moves elements in the
/// stacking order.
enum ZOrderMove {
  /// In front of every other element.
  toFront,

  /// One step forward, past the element just in front.
  forward,

  /// One step back, behind the element just behind.
  backward,

  /// Behind every other element.
  toBack,
}
