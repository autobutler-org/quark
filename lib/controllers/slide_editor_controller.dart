import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
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

/// Asks the user for a picture on this device; null when they cancel.
typedef PickImageFileFn = Future<SlideImagePick?> Function();

/// Uploads a picture beside the presentation at a path.
typedef UploadImageFn =
    Future<SlideImageUpload> Function(
      String presentationPath, {
      required String name,
      required Stream<List<int>> bytes,
      required int length,
      String? serial,
      void Function(double sent)? onProgress,
    });

/// Reads the size of a picture on the Quark from its header.
typedef ReadImageSizeFn =
    Future<SlideImageSize?> Function(String path, {String? serial});

/// Lists a folder on the Quark.
typedef ListFolderFn =
    Future<List<FileNode>> Function(String path, {String? serial});

Future<List<FileNode>> _listFolder(String path, {String? serial}) =>
    FilesService.getFiles(path, serials: serial == null ? null : [serial]);

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
/// **Toolbar and properties panel** (#1167). The active drawing tool is
/// [tools] and the text formatting commands go through [textEditing]; both
/// are shared with the canvas, and [textEditing] is kept pointed at the
/// selected slide and elements so the toolbar can format before the canvas
/// has built. [styleSelection], [arrange], [deleteSelection],
/// [duplicateSelection], [setFrame] and [setAltText] act on the selection
/// through the document, each as one undo step that starts the autosave.
/// Undo and redo write an open text editing session first, so the step it
/// makes exists before history moves.
///
/// **Pictures** (#1158). [insertImageFromDevice] picks a file, streams it up
/// beside the presentation and puts it on the slide at the size its header
/// gives; [insertImageFromQuark] does the same for a file already on the
/// Quark, without the upload. [imageUpload] says how far an upload has got;
/// a failure goes to [onImageInsertFailed].
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
    this.fontFamilies = defaultFontFamilies,
    this.pickImageFile = SlidesService.pickImageFile,
    this.uploadImage = SlidesService.uploadImage,
    this.readImageSize = SlidesService.readImageSize,
    this.listFolder = _listFolder,
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

  /// The font families the toolbar offers.
  final List<String> fontFamilies;

  /// Asks the user for a picture on this device.
  final PickImageFileFn pickImageFile;

  /// Uploads a picture beside the presentation.
  final UploadImageFn uploadImage;

  /// Reads the size of a picture on the Quark.
  final ReadImageSizeFn readImageSize;

  /// Lists a folder on the Quark, for picking a picture there.
  final ListFolderFn listFolder;

  /// Called with the thrown object when a save fails.
  void Function(Object error)? onSaveFailed;

  /// Called with the thrown object when a picture cannot be put on a slide.
  void Function(Object error)? onImageInsertFailed;

  /// The tool the canvas draws with, shared with the toolbar.
  final SlideToolController tools = SlideToolController();

  /// The canvas's text editing session and the toolbar's text formatting
  /// commands.
  late final SlideTextEditingController textEditing =
      SlideTextEditingController(fontFamilies: fontFamilies);

  /// The families the toolbar offers by default: the generic ones every
  /// platform can draw.
  static const defaultFontFamilies = ['sans-serif', 'serif', 'monospace'];

  /// The size of text whose runs set none, as the canvas draws it.
  static final double inheritedFontSize = const SlideTextLayout().fontSize;

  /// The font sizes the toolbar's stepper moves between, in slide units.
  static const fontSizes = <double>[
    12,
    14,
    16,
    18,
    20,
    24,
    28,
    32,
    36,
    40,
    48,
    56,
    64,
    72,
    96,
    120,
    144,
    200,
  ];

  /// The smallest font size the toolbar sets.
  static final double minFontSize = fontSizes.first;

  /// The largest font size the toolbar sets.
  static final double maxFontSize = fontSizes.last;

  /// How far [duplicateSelection] offsets a copy, in slide units.
  static const duplicateOffset = 16.0;

  /// The shape a picture goes in at when its header gives no size; the
  /// picture is fitted inside it, so it is never stretched.
  static const SlideImageSize fallbackImageSize = (width: 1600, height: 1200);

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
  bool _propertiesOpen = true;
  ({String name, double progress})? _imageUpload;

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

  /// The selected elements, back to front.
  List<SlideElement> get selectedElements => [
    ...?selectedSlide?.elements.where(
      (e) => _selectedElementIds.contains(e.id),
    ),
  ];

  /// The selected element when exactly one is selected, else null: what the
  /// properties panel's position, size and alt text fields edit.
  SlideElement? get singleSelected {
    final selected = selectedElements;
    return selected.length == 1 ? selected.single : null;
  }

  /// Whether the selection holds a shape or a line for [styleSelection].
  bool get hasShapesOrLines =>
      selectedElements.any((e) => e is ShapeElement || e is LineElement);

  /// What the selected shapes and lines share, for the toolbar's controls.
  ElementStyle get selectionStyle => elementStyleOf(selectedElements);

  /// The selected text's size: a shared size, [inheritedFontSize] when it
  /// sets none, or null when the selection mixes sizes.
  double? get fontSize {
    final size = textEditing.selectionFormat.fontSize;
    if (size is double) return size;
    return size == null ? inheritedFontSize : null;
  }

  /// Whether the properties panel is showing beside the canvas.
  bool get propertiesOpen => _propertiesOpen;

  /// The picture being uploaded and the share of it sent, or null.
  ({String name, double progress})? get imageUpload => _imageUpload;

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
    textEditing.commit();
    _selectedSlideId = slideId;
    _selectedElementIds = const {};
    _attachText();
  }

  /// Points [textEditing] at the selected slide and elements, as the canvas
  /// does when it builds, so the toolbar reads the selection at once.
  void _attachText() {
    final doc = _doc;
    final slideId = _selectedSlideId;
    if (doc != null && slideId != null) {
      textEditing.attach(doc.controller, slideId, _selectedElementIds);
    }
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
    textEditing.commit();
    final selected = selectedIndex;
    if (_doc?.controller.undo() ?? false) _keepSelection(selected);
  }

  /// Puts back the last edit [undo] took back.
  void redo() {
    _commitNotes();
    textEditing.commit();
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
    _attachText();
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

  // ── Toolbar and properties ────────────────────────────────────────────────

  /// Makes [tool] the one the canvas draws with.
  void useTool(SlideCanvasTool tool) => tools.use(tool);

  /// Runs [edit] on the selected slide's document when there is a
  /// selection.
  void _onSelection(
    void Function(SlideDocumentController doc, String slideId) edit,
  ) {
    final doc = _doc;
    final slideId = _selectedSlideId;
    if (doc == null || slideId == null || _selectedElementIds.isEmpty) return;
    edit(doc.controller, slideId);
  }

  /// Restyles the selected shapes and lines; other elements are skipped.
  void styleSelection(ElementStyle style) => _onSelection(
    (doc, slideId) => doc.styleElements(slideId, _selectedElementIds, style),
  );

  /// Sets the selected text's size, kept within [minFontSize] and
  /// [maxFontSize].
  void setFontSize(double size) => textEditing.format(
    TextFormat(fontSize: size.clamp(minFontSize, maxFontSize).toDouble()),
  );

  /// Moves the selected text's size to the next of [fontSizes] up
  /// ([direction] 1) or down (-1).
  void stepFontSize(int direction) {
    final current = fontSize ?? inheritedFontSize;
    final next = direction > 0
        ? fontSizes.firstWhere((s) => s > current, orElse: () => maxFontSize)
        : fontSizes.lastWhere((s) => s < current, orElse: () => minFontSize);
    setFontSize(next);
  }

  /// Restacks the selection.
  void arrange(ZOrderMove move) => _onSelection(
    (doc, slideId) => doc.arrangeElements(slideId, _selectedElementIds, move),
  );

  /// Deletes the selected elements.
  void deleteSelection() => _onSelection(
    (doc, slideId) => doc.deleteElements(slideId, _selectedElementIds),
  );

  /// Copies the selected elements in front of everything, offset by
  /// [duplicateOffset], and selects the copies.
  void duplicateSelection() => _onSelection((doc, slideId) {
    final ids = doc.batch(
      () => [for (final e in selectedElements) _addCopy(doc, slideId, e)],
    );
    selectElements(ids.toSet());
  });

  String _addCopy(SlideDocumentController doc, String slideId, SlideElement e) {
    final id = doc.newId();
    doc.addElement(
      slideId,
      e
          .withId(id)
          .withFrame(e.frame.translate(duplicateOffset, duplicateOffset)),
    );
    return id;
  }

  /// Gives the one selected element ([singleSelected]) the position, size
  /// or rotation given, as one step; a size below zero is kept at zero.
  void setFrame({
    double? x,
    double? y,
    double? width,
    double? height,
    double? rotation,
  }) {
    final element = singleSelected;
    if (element == null) return;
    _onSelection((doc, slideId) {
      final frame = element.frame;
      doc.batch(() {
        if (x != null || y != null || width != null || height != null) {
          doc.resizeElement(
            slideId,
            element.id,
            x: x,
            y: y,
            width: math.max(0, width ?? frame.width),
            height: math.max(0, height ?? frame.height),
          );
        }
        if (rotation != null) doc.rotateElement(slideId, element.id, rotation);
      });
    });
  }

  /// Sets the one selected image's alt text, which a screen reader reads
  /// for it.
  void setAltText(String altText) {
    final image = singleSelected;
    if (image is! ImageElement || image.altText == altText) return;
    _onSelection((doc, slideId) => doc.setAltText(slideId, image.id, altText));
  }

  /// Shows or hides the properties panel beside the canvas.
  void toggleProperties() {
    _propertiesOpen = !_propertiesOpen;
    _notify();
  }

  // ── Pictures ──────────────────────────────────────────────────────────────

  /// Asks for a picture on this device, uploads it beside the presentation
  /// and puts it on the selected slide — in [within], the box the image tool
  /// drew, or centered — selected. Nothing happens when the user cancels.
  Future<void> insertImageFromDevice({ElementFrame? within}) =>
      _insertImage(within, () async {
        final pick = await pickImageFile();
        if (pick == null) return null;
        _imageUpload = (name: pick.name, progress: 0);
        _notify();
        return uploadImage(
          filePath,
          name: pick.name,
          bytes: pick.bytes(),
          length: pick.length,
          serial: _serial,
          onProgress: (sent) {
            _imageUpload = (name: pick.name, progress: sent);
            _notify();
          },
        );
      });

  /// The folder the presentation is in, where picking a picture on the
  /// Quark starts.
  String get folderPath => parentPath(filePath);

  /// Lists the folder at [path] on the presentation's device.
  Future<List<FileNode>> listImageFolder(String path) =>
      listFolder(path, serial: _serial);

  /// Puts the picture at [path] on the Quark (relative to the files root of
  /// the presentation's device) on the selected slide, as
  /// [insertImageFromDevice] does after its upload.
  Future<void> insertImageFromQuark(String path, {ElementFrame? within}) =>
      _insertImage(
        within,
        () async =>
            (path: path, size: await readImageSize(path, serial: _serial)),
      );

  Future<void> _insertImage(
    ElementFrame? within,
    Future<SlideImageUpload?> Function() fetch,
  ) async {
    final slideId = _selectedSlideId;
    if (_doc == null || slideId == null) return;
    try {
      final picture = await fetch();
      final doc = _doc;
      if (picture == null || doc == null || _disposed) return;
      // The slide it was picked for may have gone while it uploaded.
      if (presentation?.slideById(slideId) == null) return;
      final id = doc.controller.insertImage(
        slideId,
        QuarkFileImage(picture.path),
        picture.size ?? fallbackImageSize,
        within: within,
      );
      if (slideId == _selectedSlideId) selectElements({id});
    } catch (e) {
      if (!_disposed) onImageInsertFailed?.call(e);
    } finally {
      _imageUpload = null;
      _notify();
    }
  }

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
      _attachText();
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
    tools.dispose();
    textEditing.dispose();
    super.dispose();
  }
}
