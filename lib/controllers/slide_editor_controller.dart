import 'dart:async';

import 'package:flutter/foundation.dart';
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
/// selection and commands, undo and redo, and the autosave.
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
    this.autosaveDelay = const Duration(seconds: 2),
    this.newId,
  });

  /// The presentation's path, relative to the device's files root.
  final String filePath;

  /// The device the file is on; empty for the Quark's own storage.
  final String deviceSerial;
  final LoadPresentationFn loadPresentation;
  final SavePresentationFn savePresentation;

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
  Timer? _autosaveTimer;
  bool _disposed = false;

  String? get _serial => deviceSerial.isEmpty ? null : deviceSerial;

  /// Whether the presentation is still being fetched.
  bool get isLoading => _isLoading;

  /// The thrown object when the presentation could not be opened, not its
  /// message — the page decides whether it means "your Quark is unreachable"
  /// or "the request failed" (#1637).
  Object? get loadError => _loadError;

  /// The thrown object from the last failed save; null once one succeeds.
  Object? get saveError => _saveError;

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

  /// Whether [undo] would do anything.
  bool get canUndo => _doc?.controller.canUndo ?? false;

  /// Whether [redo] would do anything.
  bool get canRedo => _doc?.controller.canRedo ?? false;

  /// Whether a slide can be deleted. The last one cannot: a presentation
  /// always keeps a slide to show.
  bool get canDeleteSlide => slides.length > 1;

  /// Whether the presentation differs from the file on the Quark.
  bool get isDirty {
    final current = presentation;
    return current != null && !identical(current, _saved);
  }

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
      _selectedSlideId = loaded.slides.firstOrNull?.id;
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
    _selectedSlideId = slideId;
    _notify();
  }

  /// Adds a blank slide after the selected one and selects it.
  void addSlide() {
    final doc = _doc;
    if (doc == null) return;
    final at = selectedIndex + 1;
    _selectedSlideId = doc.controller.addSlide(
      index: at == 0 ? slides.length : at,
    );
    _notify();
  }

  /// Copies the slide [slideId] in after itself and selects the copy.
  void duplicateSlide(String slideId) {
    final doc = _doc;
    if (doc == null) return;
    _selectedSlideId = doc.controller.duplicateSlide(slideId);
    _notify();
  }

  /// Deletes the slide [slideId], unless it is the last one. The selection
  /// moves to the slide that took its place, or the one before at the end.
  void deleteSlide(String slideId) {
    final doc = _doc;
    if (doc == null || !canDeleteSlide) return;
    final index = presentation!.indexOfSlide(slideId);
    if (index < 0) return;
    doc.controller.deleteSlide(slideId);
    if (slideId == _selectedSlideId) {
      _selectedSlideId = slides[index.clamp(0, slides.length - 1)].id;
    }
    _notify();
  }

  /// Moves the slide [slideId] to [toIndex] in show order.
  void moveSlide(String slideId, int toIndex) {
    final doc = _doc;
    if (doc == null || presentation!.indexOfSlide(slideId) < 0) return;
    doc.controller.moveSlide(slideId, toIndex.clamp(0, slides.length - 1));
  }

  // ── History ───────────────────────────────────────────────────────────────

  /// Takes back the last edit.
  void undo() {
    final selected = selectedIndex;
    if (_doc?.controller.undo() ?? false) _keepSelection(selected);
  }

  /// Puts back the last edit [undo] took back.
  void redo() {
    final selected = selectedIndex;
    if (_doc?.controller.redo() ?? false) _keepSelection(selected);
  }

  /// After a history step, keeps the selected slide when it still exists,
  /// and otherwise selects whatever is now at its old position.
  void _keepSelection(int previousIndex) {
    if (selectedSlide != null || slides.isEmpty) return;
    _selectedSlideId = slides[previousIndex.clamp(0, slides.length - 1)].id;
    _notify();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _onDocumentChanged() {
    _autosaveTimer?.cancel();
    if (isDirty) _autosaveTimer = Timer(autosaveDelay, save);
    _notify();
  }

  /// Saves now, without waiting for the autosave. Returns whether the
  /// presentation on screen is saved once it finishes; a failure is also
  /// reported through [saveError] and [onSaveFailed].
  Future<bool> save() async {
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
