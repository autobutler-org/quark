import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark_slides/quark_slides.dart';

/// Downloads and decodes the presentation at a path.
typedef LoadPresentationFn =
    Future<Presentation> Function(String path, {String? serial});

/// Saves a presentation over the file at a path.
typedef SavePresentationFn =
    Future<void> Function(
      String path,
      Presentation presentation, {
      String? serial,
    });

/// The URL a file on the Quark is downloaded from, authenticated.
typedef MediaUrlFn = Uri Function(String path, {String? serial});

/// Where the open presentation stands against the file on the Quark.
enum SlideSaveState {
  /// Nothing to save: the file holds what is on screen.
  saved,

  /// Edited since the last save; the autosave is waiting for a pause.
  dirty,

  /// A save is on its way to the Quark.
  saving,

  /// The last save failed. The edits are still here and still unsaved.
  failed,
}

/// State behind the slide editor: loading the `.qslide`, the slide panel's
/// selection and commands, the canvas's element selection and zoom, undo and
/// redo, and the autosave.
///
/// Every edit goes through the package's `SlideDocumentController`, so each
/// one is a step [undo] can take back. An edit marks the presentation dirty
/// and (re)starts a [autosaveDelay] timer, the two-second pause the sheets
/// editor waits for; an edit made while a save is in flight is saved once it
/// lands. Whether there is anything to save is whether the presentation is
/// the one last saved: the model is immutable, so undoing back to it leaves
/// nothing to save.
///
/// A failed save leaves [saveState] at [SlideSaveState.failed] with
/// [saveError] set, and calls [onSaveFailed] so the page can say so. The next
/// edit, or [save], tries again.
///
/// The canvas edits [document] directly, so its edits take the same path as
/// the panel's: each is an undo step, marks the presentation dirty and starts
/// the autosave. Which elements are selected lives here rather than in the
/// canvas, so the panel, the toolbar and a properties panel read the same
/// set; it empties when another slide is shown and drops ids an edit or an
/// undo took off the slide.
///
/// Speaker notes (#1166) are typed into a field under the canvas through
/// [editNotes]. Typing is held for [notesDelay] and then written to the slide
/// as one undo step, so a sentence undoes as a sentence and not a letter at
/// a time; showing another slide, an undo, a save or leaving writes it at
/// once. While it is held, [notes] reads the typing, [canUndo] is true and
/// the presentation is dirty.
///
/// Service calls are parameters defaulting to [SlidesService], so a test
/// passes fakes.
class SlideEditorController extends ChangeNotifier {
  /// Creates a controller for the presentation at [filePath] on the device
  /// [deviceSerial] (empty for the Quark's own storage). Call [load] to open it.
  SlideEditorController({
    required this.filePath,
    this.deviceSerial = '',
    this.loadPresentation = SlidesService.load,
    this.savePresentation = SlidesService.save,
    this.mediaUrl = FilesService.constructMediaUrl,
    this.autosaveDelay = const Duration(seconds: 2),
    this.newId,
  });

  /// The presentation's path, relative to the device's files root.
  final String filePath;

  /// The device the file is on; empty for the Quark's own storage.
  final String deviceSerial;
  final LoadPresentationFn loadPresentation;
  final SavePresentationFn savePresentation;

  /// Builds the download URL a picture on a slide is fetched from.
  final MediaUrlFn mediaUrl;

  /// How long editing has to pause before the autosave runs.
  final Duration autosaveDelay;

  /// Generates ids for new slides; the package's random ids by default.
  final String Function()? newId;

  /// Called with the thrown object when a save fails.
  void Function(Object error)? onSaveFailed;

  SlideDocumentNotifier? _doc;
  Presentation? _saved;
  bool _isLoading = true;
  Object? _loadError;
  Object? _saveError;
  bool _saving = false;
  String? _selectedSlideId;
  Set<String> _selectedElementIds = const {};
  double _zoom = 1;
  Timer? _autosaveTimer;
  bool _disposed = false;
  bool _notesOpen = false;
  ({String slideId, String text})? _pendingNotes;
  Timer? _notesTimer;

  /// How long typing in the notes pauses before it becomes an undo step.
  static const notesDelay = Duration(milliseconds: 500);

  String? get _serial => deviceSerial.isEmpty ? null : deviceSerial;

  /// Whether the presentation is still being fetched.
  bool get isLoading => _isLoading;

  /// The thrown object when the presentation could not be opened, not its
  /// message — the page decides whether it means "your Quark is unreachable"
  /// or "the request failed" (#1637).
  Object? get loadError => _loadError;

  /// The thrown object from the last failed save; null once one succeeds.
  Object? get saveError => _saveError;

  /// The document the canvas edits, or null before the presentation has
  /// loaded.
  SlideDocumentNotifier? get document => _doc;

  /// The presentation as edited, or null before it has loaded.
  Presentation? get presentation => _doc?.presentation;

  /// The slides in show order; empty before the presentation has loaded.
  List<Slide> get slides => presentation?.slides ?? const [];

  /// The id of the slide the canvas shows.
  String? get selectedSlideId => _selectedSlideId;

  /// The slide the canvas shows, or null when there are no slides.
  Slide? get selectedSlide {
    final id = _selectedSlideId;
    return id == null ? null : presentation?.slideById(id);
  }

  /// The position of [selectedSlide] in [slides], or -1.
  int get selectedIndex {
    final id = _selectedSlideId;
    return id == null ? -1 : presentation?.indexOfSlide(id) ?? -1;
  }

  /// The ids of the elements selected on the canvas, all on [selectedSlide].
  Set<String> get selectedElementIds => _selectedElementIds;

  /// The canvas zoom relative to fitting the slide in its box: 1 fits.
  double get zoom => _zoom;

  /// [zoom] as the bar shows it, such as `125%`.
  String get zoomPercent => '${(_zoom * 100).round()}%';

  /// Whether [zoomIn] would do anything.
  bool get canZoomIn => _zoom < SlideCanvas.maxZoom;

  /// Whether [zoomOut] would do anything.
  bool get canZoomOut => _zoom > SlideCanvas.minZoom;

  /// The zooms the bar's buttons step between, from [SlideCanvas.minZoom]
  /// to [SlideCanvas.maxZoom].
  static const zoomLevels = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  /// Whether [undo] would do anything.
  bool get canUndo =>
      _pendingNotes != null || (_doc?.controller.canUndo ?? false);

  /// Whether [redo] would do anything.
  bool get canRedo => _doc?.controller.canRedo ?? false;

  /// Whether a slide can be deleted. The last one cannot: a presentation
  /// always keeps a slide to show.
  bool get canDeleteSlide => slides.length > 1;

  /// Whether the presentation differs from the file on the Quark.
  bool get isDirty {
    final current = presentation;
    return current != null &&
        (_pendingNotes != null || !identical(current, _saved));
  }

  /// The selected slide's speaker notes, with any typing not yet written to
  /// it.
  String get notes {
    final pending = _pendingNotes;
    if (pending != null && pending.slideId == _selectedSlideId) {
      return pending.text;
    }
    return selectedSlide?.notes ?? '';
  }

  /// Whether the notes panel under the canvas is open.
  bool get notesOpen => _notesOpen;

  /// Where the presentation stands against the file on the Quark.
  SlideSaveState get saveState {
    if (_saving) return SlideSaveState.saving;
    if (!isDirty) return SlideSaveState.saved;
    return _saveError != null ? SlideSaveState.failed : SlideSaveState.dirty;
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  /// Fetches the presentation, replacing whatever was open.
  Future<void> load() async {
    _isLoading = true;
    _loadError = null;
    _notify();
    try {
      final loaded = await loadPresentation(filePath, serial: _serial);
      if (_disposed) return;
      _doc?.dispose();
      _doc = SlideDocumentNotifier(loaded, newId: newId)
        ..addListener(_onDocumentChanged);
      _saved = loaded;
      _saveError = null;
      _showSlide(loaded.slides.firstOrNull?.id);
    } catch (e) {
      _loadError = e;
    }
    _isLoading = false;
    _notify();
  }

  // ── Slide panel ───────────────────────────────────────────────────────────

  /// Shows the slide [slideId] on the canvas.
  void selectSlide(String slideId) {
    if (slideId == _selectedSlideId) return;
    _commitNotes();
    _showSlide(slideId);
    _notify();
  }

  /// Shows the slide before the selected one; nothing at the first.
  void selectPreviousSlide() => _step(-1);

  /// Shows the slide after the selected one; nothing at the last.
  void selectNextSlide() => _step(1);

  void _step(int by) {
    final to = selectedIndex + by;
    if (selectedIndex < 0 || to < 0 || to >= slides.length) return;
    selectSlide(slides[to].id);
  }

  /// Makes [slideId] the selected slide, with no elements selected on it.
  void _showSlide(String? slideId) {
    _commitNotes();
    _selectedSlideId = slideId;
    _selectedElementIds = const {};
  }

  /// Adds a blank slide after the selected one and selects it.
  void addSlide() {
    final doc = _doc;
    if (doc == null) return;
    _commitNotes();
    final at = selectedIndex + 1;
    _showSlide(doc.controller.addSlide(index: at == 0 ? slides.length : at));
    _notify();
  }

  /// Copies the slide [slideId] in after itself and selects the copy.
  void duplicateSlide(String slideId) {
    final doc = _doc;
    if (doc == null) return;
    _commitNotes();
    _showSlide(doc.controller.duplicateSlide(slideId));
    _notify();
  }

  /// Deletes the slide [slideId], unless it is the last one. The selection
  /// moves to the slide that took its place, or the one before at the end.
  void deleteSlide(String slideId) {
    final doc = _doc;
    if (doc == null || !canDeleteSlide) return;
    final index = presentation!.indexOfSlide(slideId);
    if (index < 0) return;
    _commitNotes();
    doc.controller.deleteSlide(slideId);
    if (slideId == _selectedSlideId) {
      _showSlide(slides[index.clamp(0, slides.length - 1)].id);
    }
    _notify();
  }

  /// Moves the slide [slideId] to [toIndex] in show order.
  void moveSlide(String slideId, int toIndex) {
    final doc = _doc;
    if (doc == null || presentation!.indexOfSlide(slideId) < 0) return;
    _commitNotes();
    doc.controller.moveSlide(slideId, toIndex.clamp(0, slides.length - 1));
  }

  // ── History ───────────────────────────────────────────────────────────────

  /// Takes back the last edit.
  void undo() {
    _commitNotes();
    final selected = selectedIndex;
    if (_doc?.controller.undo() ?? false) _keepSelection(selected);
  }

  /// Puts back the last edit [undo] took back.
  void redo() {
    _commitNotes();
    final selected = selectedIndex;
    if (_doc?.controller.redo() ?? false) _keepSelection(selected);
  }

  /// After a history step, keeps the selected slide when it still exists,
  /// and otherwise selects whatever is now at its old position.
  void _keepSelection(int previousIndex) {
    if (selectedSlide != null || slides.isEmpty) return;
    _showSlide(slides[previousIndex.clamp(0, slides.length - 1)].id);
    _notify();
  }

  // ── Canvas ────────────────────────────────────────────────────────────────

  /// Selects the elements [ids] on the selected slide.
  void selectElements(Set<String> ids) {
    if (setEquals(ids, _selectedElementIds)) return;
    _selectedElementIds = Set.unmodifiable(ids);
    _notify();
  }

  /// Sets the canvas zoom, kept within [SlideCanvas.minZoom] and
  /// [SlideCanvas.maxZoom].
  void setZoom(double zoom) {
    final next = zoom.clamp(SlideCanvas.minZoom, SlideCanvas.maxZoom);
    if (next == _zoom) return;
    _zoom = next;
    _notify();
  }

  /// Zooms to the next of [zoomLevels] above the current zoom.
  void zoomIn() =>
      setZoom(zoomLevels.firstWhere((z) => z > _zoom, orElse: () => _zoom));

  /// Zooms to the next of [zoomLevels] below the current zoom.
  void zoomOut() =>
      setZoom(zoomLevels.lastWhere((z) => z < _zoom, orElse: () => _zoom));

  /// Fits the whole slide in the canvas again.
  void zoomToFit() => setZoom(1);

  /// The URL of the picture a slide names by [source], a path relative to
  /// the files root of the device the presentation is on.
  Uri imageUrl(String source) =>
      mediaUrl(source.trim().replaceAll(RegExp(r'^/+'), ''), serial: _serial);

  // ── Speaker notes ─────────────────────────────────────────────────────────

  /// Replaces the selected slide's speaker notes with [text], written to the
  /// slide once typing pauses for [notesDelay].
  void editNotes(String text) {
    final slideId = _selectedSlideId;
    if (_doc == null || slideId == null) return;
    final wasPending = _pendingNotes != null;
    _pendingNotes = (slideId: slideId, text: text);
    _notesTimer?.cancel();
    _notesTimer = Timer(notesDelay, _commitNotes);
    // The save chip and undo change once, not on every key.
    if (!wasPending) {
      _autosaveTimer?.cancel();
      _notify();
    }
  }

  /// Writes held typing to its slide as one undo step.
  void _commitNotes() {
    _notesTimer?.cancel();
    final pending = _pendingNotes;
    if (pending == null) return;
    _pendingNotes = null;
    final slide = presentation?.slideById(pending.slideId);
    if (slide == null) return;
    if (slide.notes == pending.text) {
      // Typed back to what it was: no step to record, but the save chip and
      // undo stop counting the typing.
      _onDocumentChanged();
    } else {
      _doc!.controller.setSlideNotes(pending.slideId, pending.text);
    }
  }

  /// Opens or closes the notes panel under the canvas.
  void toggleNotes() {
    _notesOpen = !_notesOpen;
    _notify();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _onDocumentChanged() {
    // An edit or an undo may have taken selected elements off the slide.
    final onSlide = {...?selectedSlide?.elements.map((e) => e.id)};
    if (!_selectedElementIds.every(onSlide.contains)) {
      _selectedElementIds = Set.unmodifiable(
        _selectedElementIds.where(onSlide.contains),
      );
    }
    _autosaveTimer?.cancel();
    if (isDirty) _autosaveTimer = Timer(autosaveDelay, save);
    _notify();
  }

  /// Saves now, without waiting for the autosave. Returns whether the
  /// presentation on screen is saved once it finishes; a failure is also
  /// reported through [saveError] and [onSaveFailed].
  Future<bool> save() async {
    _commitNotes();
    _autosaveTimer?.cancel();
    final current = presentation;
    if (current == null || _saving || !isDirty) return !isDirty;
    _saving = true;
    _notify();
    try {
      await savePresentation(filePath, current, serial: _serial);
      _saved = current;
      _saveError = null;
    } catch (e) {
      _saveError = e;
      onSaveFailed?.call(e);
    }
    _saving = false;
    _notify();
    // Edits made while that save was in flight wait for the next one.
    if (_saveError == null && isDirty && !_disposed) {
      _autosaveTimer = Timer(autosaveDelay, save);
    }
    return !isDirty;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Stops the autosave. Edits still waiting for it are saved on the way
  /// out, so leaving the editor inside the pause loses nothing.
  @override
  void dispose() {
    _commitNotes();
    final pending = _autosaveTimer?.isActive ?? false;
    _autosaveTimer?.cancel();
    final current = presentation;
    if (pending && current != null && !_saving) {
      unawaited(
        savePresentation(
          filePath,
          current,
          serial: _serial,
        ).catchError((Object _) {}),
      );
    }
    _disposed = true;
    _doc?.dispose();
    super.dispose();
  }
}
