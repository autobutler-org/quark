import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/fullscreen.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_slides/quark_slides.dart';

/// The URL one picture inside an office package is fetched from.
///
/// [part] is the zip entry (`ppt/media/image3.png`). [filePath] is the
/// package on the device [serial] (null for the Quark's own storage).
typedef PartUrlFn =
    Uri Function(String part, {required String filePath, String? serial});

/// Builds a [PartUrlFn] for `GET /api/v0/previews/part`.
///
/// The bearer token is added when the app holds one, so an image widget,
/// which cannot send an Authorization header, can still authenticate.
Uri previewPartUrl(String part, {required String filePath, String? serial}) {
  final querySegments = <String>[
    'filePath=${Uri.encodeQueryComponent(filePath)}',
    'part=${Uri.encodeQueryComponent(part)}',
  ];
  final serialValue = serial?.trim() ?? '';
  if (serialValue.isNotEmpty) {
    querySegments.add('serial=${Uri.encodeQueryComponent(serialValue)}');
  }
  final token = AppSettings.instance.bearerToken;
  if (token != null && token.isNotEmpty) {
    querySegments.add('token=${Uri.encodeQueryComponent(token)}');
  }
  return apiBaseUri
      .resolve('/api/v0/previews/part')
      .replace(query: querySegments.join('&'));
}

/// State behind presenting a `.qslide` (#1165): the presentation, the slide
/// showing, the presenter view with its clock, the control bar that hides
/// when the pointer rests, and fullscreen.
///
/// Handed a deck as [initial] — the editor's unsaved copy, or a deck a
/// viewer already converted — it shows that deck at once. Opened from a
/// link, it loads the file. It never edits: speaker notes are read here,
/// written in the editor (#1166).
///
/// Each step plays the [transition] of the slide it arrives at, mirrored
/// when it goes back ([movedBack]).
///
/// The clock counts whole seconds from when the presentation is on screen,
/// through [elapsed], so only the clock rebuilds each second. The controls
/// are visible for [controlsIdle] after the last [wakeControls].
///
/// Service calls and fullscreen are parameters, so a test passes fakes.
class SlidePresentController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller for the file at [filePath] on the device
  /// [deviceSerial] (empty for the Quark's own storage), from the slide at
  /// [startIndex].
  ///
  /// [initial] is a deck already in memory: the editor's copy, or one a
  /// viewer converted. Without one, call [load] to open the file.
  SlidePresentController({
    required this.filePath,
    this.deviceSerial = '',
    this.startIndex = 0,
    Presentation? initial,
    this.loadPresentation = SlidesService.load,
    this.mediaUrl = FilesService.constructMediaUrl,
    this.partUrl = previewPartUrl,
    this.fullscreen = const FullscreenControl(),
  }) {
    if (initial != null) _show(initial);
  }

  /// How long the controls stay after the pointer last moved.
  static const controlsIdle = Duration(seconds: 3);

  /// The presentation's path, relative to the device's files root.
  final String filePath;

  /// The device the file is on; empty for the Quark's own storage.
  final String deviceSerial;

  /// The slide to start at, counting from 0; clamped to the slides there are.
  final int startIndex;
  final LoadPresentationFn loadPresentation;

  /// Builds the download URL a picture on a slide is fetched from.
  final MediaUrlFn mediaUrl;

  /// Builds the URL a picture inside the file at [filePath] is fetched from.
  final PartUrlFn partUrl;

  /// The platform's fullscreen switch.
  final FullscreenControl fullscreen;

  /// Time on screen, in whole seconds, since the presentation appeared.
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  Presentation? _presentation;
  Object? _loadError;
  int _index = 0;
  bool _movedBack = false;
  bool _presenterView = false;
  bool _controlsVisible = true;
  Timer? _clock;
  Timer? _idle;

  String? get _serial => deviceSerial.isEmpty ? null : deviceSerial;

  /// Whether the presentation is still being fetched.
  bool get isLoading => _presentation == null && _loadError == null;

  /// The thrown object when the presentation could not be opened.
  Object? get loadError => _loadError;

  /// The presentation, or null before it has loaded.
  Presentation? get presentation => _presentation;

  /// The slides in show order; empty before the presentation has loaded.
  List<Slide> get slides => _presentation?.slides ?? const [];

  /// The position of [currentSlide] in [slides].
  int get index => _index;

  /// The slide on screen, or null before the presentation has loaded.
  Slide? get currentSlide => slides.isEmpty ? null : slides[_index];

  /// The slide after [currentSlide], or null at the last.
  Slide? get nextSlide =>
      _index + 1 < slides.length ? slides[_index + 1] : null;

  /// The transition [currentSlide] comes on with: its own, or the deck's
  /// default; none before the presentation has loaded.
  SlideTransitionSpec get transition {
    final slide = currentSlide;
    return slide == null
        ? SlideTransitionSpec.none
        : _presentation!.transitionFor(slide);
  }

  /// Whether the show last stepped back, to an earlier slide, which plays
  /// [transition] in reverse.
  bool get movedBack => _movedBack;

  /// Whether [currentSlide] is the first.
  bool get isFirst => _index == 0;

  /// Whether [currentSlide] is the last.
  bool get isLast => _index >= slides.length - 1;

  /// Where the show is, such as "Slide 2 of 5".
  String get position => 'Slide ${_index + 1} of ${slides.length}';

  /// Whether the speaker's view — next slide, notes, clock — is showing.
  bool get presenterView => _presenterView;

  /// Whether the control bar is showing.
  bool get controlsVisible => _controlsVisible;

  /// Whether [toggleFullscreen] can do anything here.
  bool get canToggleFullscreen => fullscreen.isSupported;

  /// Whether the app is fullscreen.
  bool get isFullscreen => fullscreen.isSupported && fullscreen.isActive;

  /// The URL of the picture a slide names by [source].
  ///
  /// A file in the Quark, and an uploaded asset, are fetched from the device
  /// the presentation is on. A [PackagePartImage] is fetched from inside the
  /// file at [filePath].
  Uri imageUrl(String source) {
    final trimmed = source.trim();
    switch (ImageSource.parse(trimmed)) {
      case PackagePartImage(:final part):
        return partUrl(part, filePath: filePath, serial: _serial);
      case QuarkFileImage() || UploadedAssetImage():
        return mediaUrl(
          trimmed.replaceAll(RegExp(r'^/+'), ''),
          serial: _serial,
        );
    }
  }

  /// Fetches the presentation, unless it was handed over already.
  Future<void> load() async {
    if (_presentation != null) return;
    _loadError = null;
    notifyListeners();
    try {
      final loaded = await loadPresentation(filePath, serial: _serial);
      if (isDisposed) return;
      _show(loaded);
    } catch (e) {
      _loadError = e;
    }
    notifyListeners();
  }

  void _show(Presentation presentation) {
    _presentation = presentation;
    final slideCount = presentation.slides.length;
    _index = slideCount == 0 ? 0 : startIndex.clamp(0, slideCount - 1);
    _clock ??= Timer.periodic(const Duration(seconds: 1), (_) {
      elapsed.value += const Duration(seconds: 1);
    });
    wakeControls();
  }

  /// Shows the slide at [index], kept within the slides there are.
  void goTo(int index) {
    if (slides.isEmpty) return;
    final to = index.clamp(0, slides.length - 1);
    if (to == _index) return;
    _movedBack = to < _index;
    _index = to;
    notifyListeners();
  }

  /// Shows the next slide; nothing at the last.
  void next() => goTo(_index + 1);

  /// Shows the previous slide; nothing at the first.
  void previous() => goTo(_index - 1);

  /// Shows the first slide.
  void first() => goTo(0);

  /// Shows the last slide.
  void last() => goTo(slides.length - 1);

  /// Shows or hides the speaker's view.
  void togglePresenterView() {
    _presenterView = !_presenterView;
    notifyListeners();
  }

  /// Shows the controls and restarts their [controlsIdle] countdown.
  void wakeControls() {
    _idle?.cancel();
    _idle = Timer(controlsIdle, () {
      _controlsVisible = false;
      notifyListeners();
    });
    if (_controlsVisible) return;
    _controlsVisible = true;
    notifyListeners();
  }

  /// Enters fullscreen, or leaves it.
  Future<void> toggleFullscreen() async {
    if (!canToggleFullscreen) return;
    await fullscreen.setActive(!fullscreen.isActive);
    notifyListeners();
  }

  /// Leaves fullscreen, on the way out of presenting.
  Future<void> leaveFullscreen() async {
    if (isFullscreen) await fullscreen.setActive(false);
  }

  /// Stops the clock and the controls' countdown.
  @override
  void dispose() {
    _clock?.cancel();
    _idle?.cancel();
    elapsed.dispose();
    super.dispose();
  }
}
