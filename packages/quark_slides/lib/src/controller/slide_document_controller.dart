import 'dart:math';

import '../model/presentation.dart';
import '../model/slide.dart';
import '../model/slide_background.dart';
import '../model/slide_element.dart';
import '../model/text_paragraph.dart';

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
  })  : _presentation = presentation,
        _generateId = newId ?? _randomId;

  /// Called after every change to [presentation], [canUndo] or [canRedo].
  void Function()? onChanged;

  /// The most undo steps kept.
  final int maxUndoDepth;

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
        for (final element in slide.elements) element.id,
      ],
    };
    final ids = <String>[];
    while (ids.length < count) {
      final id = _generateId();
      if (used.add(id)) ids.add(id);
    }
    return ids;
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
  /// copy's id. The copy and each of its elements get new ids.
  String duplicateSlide(String slideId) {
    final index = _slideIndex(slideId);
    final source = _presentation.slides[index];
    final ids = _freshIds(source.elements.length + 1);
    final copy = source.copyWith(
      id: ids.first,
      elements: [
        for (var i = 0; i < source.elements.length; i++)
          source.elements[i].withId(ids[i + 1]),
      ],
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
        (s) => s.id == id || s.elements.any((e) => e.id == id),
      );

  /// Moves every element in [elementIds] on the slide [slideId] by [dx],
  /// [dy] slide units, as one step.
  void moveElements(
    String slideId,
    Iterable<String> elementIds,
    double dx,
    double dy,
  ) {
    final ids = elementIds.toSet();
    _updateSlide(slideId, (slide) {
      for (final id in ids) {
        _elementIndex(slide, id);
      }
      return slide.copyWith(
        elements: [
          for (final e in slide.elements)
            ids.contains(e.id) ? e.withFrame(e.frame.translate(dx, dy)) : e,
        ],
      );
    });
  }

  /// Gives the element [elementId] a new size, and a new top-left corner
  /// when [x] or [y] is given — as dragging a left or top handle needs.
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
    _updateElement(
      slideId,
      elementId,
      (e) => e.withFrame(
        e.frame.copyWith(x: x, y: y, width: width, height: height),
      ),
    );
  }

  /// Sets the element [elementId]'s clockwise rotation, in degrees.
  void rotateElement(String slideId, String elementId, double degrees) =>
      _updateElement(
        slideId,
        elementId,
        (e) => e.withFrame(e.frame.copyWith(rotation: degrees)),
      );

  /// Removes every element in [elementIds] from the slide [slideId], as one
  /// step.
  void deleteElements(String slideId, Iterable<String> elementIds) {
    final ids = elementIds.toSet();
    _updateSlide(slideId, (slide) {
      for (final id in ids) {
        _elementIndex(slide, id);
      }
      return slide.copyWith(
        elements: [
          for (final e in slide.elements)
            if (!ids.contains(e.id)) e,
        ],
      );
    });
  }

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
  /// unselected neighbor.
  void arrangeElements(
    String slideId,
    Iterable<String> elementIds,
    ZOrderMove move,
  ) {
    final ids = elementIds.toSet();
    _updateSlide(slideId, (slide) {
      for (final id in ids) {
        _elementIndex(slide, id);
      }
      final elements = [...slide.elements];
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
          return slide.copyWith(
            elements: move == ZOrderMove.toFront
                ? [...rest, ...chosen]
                : [...chosen, ...rest],
          );
        case ZOrderMove.forward:
          for (var i = elements.length - 2; i >= 0; i--) {
            if (picked(i) && !picked(i + 1)) swap(i, i + 1);
          }
        case ZOrderMove.backward:
          for (var i = 1; i < elements.length; i++) {
            if (picked(i) && !picked(i - 1)) swap(i, i - 1);
          }
      }
      return slide.copyWith(elements: elements);
    });
  }

  /// Replaces the text of the text box [elementId]. Throws an
  /// [ArgumentError] when the element is not a [TextBox].
  void editText(
    String slideId,
    String elementId,
    List<TextParagraph> paragraphs,
  ) =>
      _updateElement(slideId, elementId, (e) {
        if (e is! TextBox) {
          throw ArgumentError.value(
              elementId, 'elementId', 'is not a text box');
        }
        return e.copyWith(paragraphs: List.unmodifiable(paragraphs));
      });

  // ---------------------------------------------------------------------------
  // Lookup
  // ---------------------------------------------------------------------------

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

  void _updateElement(
    String slideId,
    String elementId,
    SlideElement Function(SlideElement) update,
  ) =>
      _updateSlide(slideId, (slide) {
        final elements = [...slide.elements];
        final index = _elementIndex(slide, elementId);
        elements[index] = update(elements[index]);
        return slide.copyWith(elements: elements);
      });
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
