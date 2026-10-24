import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/controllers/video_playback_controller.dart';
import 'package:quark/services/playback_position_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/media_autoplay.dart';
import 'package:quark/utils/video_frame_capture.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/video_viewer/fullscreen_video_page.dart';
import 'package:quark/widgets/video_viewer/inline_video_player.dart';
import 'package:quark/widgets/video_viewer/convert_video.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Full-screen player for a video file on the Quark.
class VideoViewerPage extends StatefulWidget {
  final Uri url;
  final String name;

  /// Whether playback may start without the user pressing play.
  final bool Function() canAutoplay;

  /// Closes the player from its back button. Null leaves the app bar's own,
  /// which pops the route this player was pushed on.
  final VoidCallback? onClose;

  /// Reads where the user left off in this video.
  final LoadPlayback loadPlayback;

  /// Stores how far playback has reached.
  final SavePlayback savePlayback;

  /// Marks this video watched or unwatched.
  final SetPlaybackWatched setPlaybackWatched;

  /// Lists the formats [convertVideo] can offer for this file.
  final LoadTranscodeFormatsFn loadTranscodeFormats;

  /// Queues the conversion [convertVideo] starts.
  final TranscodeVideoFn transcodeVideo;

  const VideoViewerPage({
    super.key,
    required this.url,
    required this.name,
    this.canAutoplay = canAutoplayMedia,
    this.onClose,
    this.loadPlayback = PlaybackPositionService.get,
    this.savePlayback = PlaybackPositionService.save,
    this.setPlaybackWatched = PlaybackPositionService.setWatched,
    this.loadTranscodeFormats = FilesService.listTranscodeFormats,
    this.transcodeVideo = FilesService.transcodeVideo,
  });

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  VideoPlayerController? _controller;
  LocalMediaProxy? _proxy;
  // Resume position and watched state; null when the URL names no file.
  VideoPlaybackController? _playback;
  bool _loading = true;
  String? _errorMessage;
  bool _isUnsupportedFormat = false;
  bool _downloading = false;
  bool _savingFrame = false;
  // The RepaintBoundary around the video, which Save Frame captures.
  final _frameKey = GlobalKey();
  bool _trimMode = false;
  bool _exportingTrim = false;
  // Trim handles as fractions [0.0, 1.0] of total duration.
  double _trimStart = 0.0;
  double _trimEnd = 1.0;

  static const _nonWebNativeExtensions = {
    '.mov',
    '.avi',
    '.mkv',
    '.wmv',
    '.flv',
    '.3gp',
  };

  bool _isNonWebNativeFormat(String name) {
    final lower = name.toLowerCase();
    return _nonWebNativeExtensions.any((ext) => lower.endsWith(ext));
  }

  /// A player the browser accepted but that has nothing to show: no duration,
  /// no frame, or an error. That is the black picture with live controls.
  bool _hasDecodedPicture(VideoPlayerValue value) {
    return value.isInitialized &&
        !value.hasError &&
        value.duration > Duration.zero &&
        value.size.width > 0 &&
        value.size.height > 0;
  }

  /// Copy for a file that will not play, and whether Download belongs with it.
  ///
  /// A container the browser will not open names that container. A player that
  /// opened and then produced no picture names the codec. Anything else keeps
  /// the generic sentence, which does not offer a download.
  ({String message, bool offerDownload}) _playbackFailure({
    required bool opened,
  }) {
    final extension = fileExtension(widget.name);
    final ext = extension.toUpperCase();
    // A .ts file holds picture and sound the browser can play in another
    // container, so the reason names the container and never the codec.
    if (extension == '.ts') {
      return (
        message: Errors.unsupportedVideoContainer(ext),
        offerDownload: true,
      );
    }
    // .mov is in the non-web list, which is the right answer when the
    // browser refuses the file outright. Once it has opened and still has
    // no picture, the container is fine and the codec is not.
    if (_isNonWebNativeFormat(widget.name) &&
        !(opened && extension == '.mov')) {
      return (message: Errors.unsupportedVideoFormat(ext), offerDownload: true);
    }
    if (opened) {
      return (message: Errors.unsupportedVideoCodec, offerDownload: true);
    }
    return (message: Errors.unplayableMedia, offerDownload: false);
  }

  /// Drops [controller] and shows why this file will not play.
  Future<void> _failPlayback({
    required bool opened,
    VideoPlayerController? controller,
    LocalMediaProxy? proxy,
  }) async {
    if (!mounted || _errorMessage != null) {
      await controller?.dispose();
      await proxy?.close();
      return;
    }
    final failure = _playbackFailure(opened: opened);
    if (identical(_controller, controller)) _controller = null;
    if (identical(_proxy, proxy)) _proxy = null;
    setState(() {
      _loading = false;
      _errorMessage = failure.message;
      _isUnsupportedFormat = failure.offerDownload;
    });
    await controller?.dispose();
    await proxy?.close();
  }

  /// Replaces the player when a decode error arrives after it was shown.
  void _watchForDecodeError(VideoPlayerController controller) {
    controller.addListener(() {
      if (!mounted || _errorMessage != null || _controller != controller) {
        return;
      }
      if (!controller.value.hasError) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _controller != controller) return;
        _failPlayback(opened: true, controller: controller, proxy: _proxy);
      });
    });
  }

  bool _canTrim(VideoPlayerController? controller) {
    final value = controller?.value;
    return value != null &&
        value.isInitialized &&
        !value.hasError &&
        value.duration > Duration.zero;
  }

  bool _canSaveFrame(VideoPlayerController? controller) {
    final value = controller?.value;
    return value != null &&
        value.isInitialized &&
        !value.hasError &&
        value.size.width > 0 &&
        value.size.height > 0;
  }

  @override
  void initState() {
    super.initState();
    final params = widget.url.queryParameters;
    final relPath = params['filePath'] ?? '';
    if (relPath.isNotEmpty) {
      _playback = VideoPlaybackController(
        relPath: relPath,
        serial: params['serial'],
        load: widget.loadPlayback,
        save: widget.savePlayback,
        setWatched: widget.setPlaybackWatched,
      );
    }
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
      _isUnsupportedFormat = false;
    });

    VideoPlayerController? controller;
    LocalMediaProxy? proxy;
    try {
      // A quark on the local network serves a self-signed cert that AVPlayer
      // and ExoPlayer both reject. Terminate TLS in Dart, where the app's
      // local-trust exception applies, and re-serve over loopback.
      if (mediaNeedsLocalProxy(widget.url)) {
        proxy = await LocalMediaProxy.start(widget.url);
      }
      controller = VideoPlayerController.networkUrl(
        proxy?.localUrl ?? widget.url,
        formatHint: _formatHintFromFileName(widget.name),
      );
      await controller.initialize();
    } catch (e) {
      debugPrint('[video_viewer_page.dart] initialize error: $e');
      // A 404 or a 401 is not a codec problem, and issue #1627 is precisely
      // about that mislabelling. Prefer whatever the server actually said.
      final upstreamError = proxy?.lastUpstreamError;
      if (upstreamError != null) {
        await controller?.dispose();
        await proxy?.close();
        if (!mounted) return;
        setState(() {
          _loading = false;
          _isUnsupportedFormat = false;
          _errorMessage = upstreamError.userMessage;
        });
        return;
      }
      await _failPlayback(opened: false, controller: controller, proxy: proxy);
      return;
    }

    if (!mounted) {
      await controller.dispose();
      await proxy?.close();
      return;
    }

    // Initialized with no duration or no frame is a black player: the
    // controls run and nothing on screen says why (#3429).
    if (!_hasDecodedPicture(controller.value)) {
      await _failPlayback(opened: true, controller: controller, proxy: proxy);
      return;
    }

    setState(() {
      _controller = controller;
      _proxy = proxy;
      _loading = false;
    });
    _watchForDecodeError(controller);

    final playback = _playback;
    if (playback != null) {
      // Bounded: a slow or failing Quark must not hold up playback.
      final resumeAt = await playback.load().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      );
      // The page's dispose has already disposed the player.
      if (!mounted) return;
      if (resumeAt != null && resumeAt < controller.value.duration) {
        await controller.seekTo(resumeAt);
        if (!mounted) return;
      }
      final player = controller;
      player.addListener(() {
        final value = player.value;
        playback.report(
          value.position,
          value.duration,
          isPlaying: value.isPlaying,
        );
      });
    }

    // Autoplay only when the browser will allow it. A tab opened straight
    // onto a video's URL has no user gesture behind it, and the browser
    // rejects play() there. video_player_web reports that rejection on the
    // event stream instead of throwing, which puts the controller into an
    // error state: the progress bar spins forever and play does nothing
    // (#2002). So a blocked play() cannot be tried and caught; skip it and
    // leave the video paused for the user to start.
    if (widget.canAutoplay()) {
      try {
        await controller.play();
      } catch (_) {
        // A native player that refuses to start leaves the video paused.
      }
    }
  }

  VideoFormat? _formatHintFromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.m3u8')) {
      return VideoFormat.hls;
    }
    if (lower.endsWith('.mpd')) {
      return VideoFormat.dash;
    }
    if (lower.endsWith('.ism') || lower.endsWith('.isml')) {
      return VideoFormat.ss;
    }
    return VideoFormat.other;
  }

  @override
  void dispose() {
    // The listener has kept the last position current; save it before the
    // player goes. The request outlives the page, its reply is dropped.
    _playback?.flush();
    _playback?.dispose();
    _controller?.dispose();
    _controller = null;
    _proxy?.close();
    _proxy = null;
    super.dispose();
  }

  Future<void> _openFullscreen() async {
    final controller = _controller;
    if (controller == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FullscreenVideoPage(controller: controller),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  List<Widget> _buildDownloadSection() {
    return [
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _downloading ? null : _downloadVideo,
        icon: _downloading
            ? const QuarkLoader(size: 16)
            : const Icon(Icons.download_rounded, size: 16),
        label: Text(_downloading ? 'Downloading…' : 'Download'),
      ),
    ];
  }

  Future<void> _downloadVideo() async {
    setState(() => _downloading = true);
    // The media URL carries the file's path and serial as query parameters;
    // its own path is the download endpoint, not the file.
    final params = widget.url.queryParameters;
    await downloadViewedFile(
      context,
      path: params['filePath'] ?? '',
      serial: params['serial'],
      name: widget.name,
    );
    if (mounted) setState(() => _downloading = false);
  }

  void _enterTrimMode() {
    final controller = _controller;
    if (controller == null || !_canTrim(controller)) {
      showMessage(context, Errors.trimUnavailable);
      return;
    }
    controller.pause();
    setState(() {
      _trimMode = true;
      _trimStart = 0.0;
      _trimEnd = 1.0;
    });
  }

  Future<void> _exportTrim() async {
    final controller = _controller;
    if (controller == null || !_canTrim(controller)) {
      showMessage(context, Errors.trimUnavailable);
      return;
    }
    if (_exportingTrim) return;

    final params = widget.url.queryParameters;
    final relPath = params['filePath'] ?? '';
    final serial = params['serial'];
    if (relPath.isEmpty) {
      showMessage(context, Errors.trimPathUnknown);
      return;
    }

    final totalMs = controller.value.duration.inMilliseconds;
    final startMs = (_trimStart * totalMs).round();
    final endMs = (_trimEnd * totalMs).round();

    setState(() => _exportingTrim = true);
    try {
      final trimmed = await FilesService.trimVideo(
        relPath,
        serial: serial,
        startMs: startMs,
        endMs: endMs,
      );
      if (!mounted) return;
      setState(() {
        _trimMode = false;
        _trimStart = 0.0;
        _trimEnd = 1.0;
      });
      showMessage(
        context,
        trimmed.savedMessage(Duration(milliseconds: startMs)),
      );
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.trim(e));
    } finally {
      if (mounted) setState(() => _exportingTrim = false);
    }
  }

  Future<void> _saveFrame() async {
    final controller = _controller;
    if (controller == null || !_canSaveFrame(controller)) {
      showMessage(context, Errors.saveFrameUnavailable);
      return;
    }
    if (_savingFrame) return;

    // Derive relPath and serial from the media URL query parameters.
    final params = widget.url.queryParameters;
    final relPath = params['filePath'] ?? '';
    final serial = params['serial'];
    if (relPath.isEmpty) {
      showMessage(context, Errors.saveFramePathUnknown);
      return;
    }

    final wasPlaying = controller.value.isPlaying;
    if (wasPlaying) await controller.pause();

    final position = controller.value.position;

    if (!mounted) return;
    setState(() => _savingFrame = true);
    try {
      // The frame is grabbed here, from the player, and uploaded like any
      // other new file beside the video: the Quark decodes no video (#2380).
      final bytes = await captureVideoFrame(controller, _frameKey);
      final name = videoFrameFileName(widget.name, position);
      final landed = await FilesService.uploadBytes(
        parentPath(relPath),
        name,
        bytes,
        serial: serial,
        keepBoth: true,
      );
      if (!mounted) return;
      final fileName = (landed.isEmpty ? name : landed.first).split('/').last;
      showMessage(context, 'Frame saved as $fileName');
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'save the frame'));
    } finally {
      if (mounted) setState(() => _savingFrame = false);
      if (wasPlaying && _controller != null) await _controller!.play();
    }
  }

  Future<void> _toggleWatched() async {
    final playback = _playback;
    if (playback == null) return;
    final wasWatched = playback.watched;
    try {
      await playback.toggleWatched();
    } catch (e) {
      if (!mounted) return;
      showMessage(
        context,
        Errors.message(
          e,
          wasWatched
              ? 'mark the video as unwatched'
              : 'mark the video as watched',
        ),
      );
    }
  }

  Future<void> _convert() {
    final params = widget.url.queryParameters;
    return convertVideo(
      context,
      relPath: params['filePath'] ?? '',
      serial: params['serial'],
      loadFormats: widget.loadTranscodeFormats,
      transcode: widget.transcodeVideo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final playback = _playback;
    // A text button is drawn in the content's accent, which the chrome is not
    // a surface for (#2740).
    final onChrome = TextButton.styleFrom(
      foregroundColor: QuarkTokens.of(context).onChrome.foreground,
    );

    return Scaffold(
      appBar: ChromeAppBar(
        leading: widget.onClose == null
            ? null
            : BackButton(onPressed: widget.onClose),
        title: Text(widget.name),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: QuarkTokens.of(context).spacingSm,
            children: [
              if (_exportingTrim)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: QuarkLoader(size: 20),
                )
              else if (_trimMode) ...[
                TextButton(
                  style: onChrome,
                  onPressed: _exportTrim,
                  child: const Text('Save Clip'),
                ),
                TextButton(
                  style: onChrome,
                  onPressed: () => setState(() {
                    _trimMode = false;
                    _trimStart = 0.0;
                    _trimEnd = 1.0;
                  }),
                  child: const Text('Cancel'),
                ),
              ] else
                MenuAnchor(
                  menuChildren: [
                    MenuItemButton(
                      key: const ValueKey('video_viewer_save_frame'),
                      onPressed: _saveFrame,
                      child: const Text('Save Frame'),
                    ),
                    MenuItemButton(
                      key: const ValueKey('video_viewer_trim'),
                      onPressed: _enterTrimMode,
                      child: const Text('Trim Clip'),
                    ),
                    // Converting is most useful for a format the player
                    // cannot open, so it is offered whether or not playback
                    // started.
                    if ((widget.url.queryParameters['filePath'] ?? '')
                        .isNotEmpty)
                      MenuItemButton(
                        key: const ValueKey('video_viewer_convert'),
                        onPressed: _convert,
                        child: const Text('Convert…'),
                      ),
                    if (playback != null)
                      ListenableBuilder(
                        listenable: playback,
                        builder: (context, _) => MenuItemButton(
                          key: ValueKey(
                            playback.watched
                                ? 'video_viewer_mark_unwatched'
                                : 'video_viewer_mark_watched',
                          ),
                          onPressed: _toggleWatched,
                          child: Text(
                            playback.watched
                                ? 'Mark as unwatched'
                                : 'Mark as watched',
                          ),
                        ),
                      ),
                  ],
                  builder: (context, controller, _) => QuarkBarIconButton(
                    key: const ValueKey('video_viewer_more'),
                    icon: QuarkIcons.more_vert,
                    tooltip: 'More options',
                    // Saving a frame spins here until the frame lands.
                    isBusy: _savingFrame,
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                ),
              const AppThemeToggle(),
            ],
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? const QuarkLoader()
            : _errorMessage != null
            ? Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isUnsupportedFormat
                          ? QuarkIcons.video_file_outlined
                          : QuarkIcons.error_outline,
                      size: 36,
                    ),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, textAlign: TextAlign.center),
                    if (_isUnsupportedFormat) ..._buildDownloadSection(),
                  ],
                ),
              )
            : controller != null
            ? InlineVideoPlayer(
                controller: controller,
                frameKey: _frameKey,
                onToggleFullscreen: _openFullscreen,
                trimMode: _trimMode,
                trimStart: _trimStart,
                trimEnd: _trimEnd,
                onTrimStartChanged: (v) => setState(() => _trimStart = v),
                onTrimEndChanged: (v) => setState(() => _trimEnd = v),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
