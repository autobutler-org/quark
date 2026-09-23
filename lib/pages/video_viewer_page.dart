import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/media_autoplay.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/video_viewer/fullscreen_video_page.dart';
import 'package:quark/widgets/video_viewer/inline_video_player.dart';
import 'package:quark/widgets/video_viewer/transcode_dialog_host.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player/video_player.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Full-screen player for a video file on the Quark.
class VideoViewerPage extends StatefulWidget {
  final Uri url;
  final String name;

  /// Whether playback may start without the user pressing play.
  final bool Function() canAutoplay;

  const VideoViewerPage({
    super.key,
    required this.url,
    required this.name,
    this.canAutoplay = canAutoplayMedia,
  });

  @override
  State<VideoViewerPage> createState() => _VideoViewerPageState();
}

class _VideoViewerPageState extends State<VideoViewerPage> {
  VideoPlayerController? _controller;
  LocalMediaProxy? _proxy;
  bool _loading = true;
  String? _errorMessage;
  bool _isUnsupportedFormat = false;
  bool _downloading = false;
  bool _savingFrame = false;
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

  String _extensionOf(String name) {
    final idx = name.lastIndexOf('.');
    if (idx < 0) return '';
    return name.substring(idx).toUpperCase();
  }

  @override
  void initState() {
    super.initState();
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
      await controller?.dispose();
      // A 404 or a 401 is not a codec problem, and issue #1627 is precisely
      // about that mislabelling. Prefer whatever the server actually said.
      final upstreamError = proxy?.lastUpstreamError;
      await proxy?.close();
      if (!mounted) {
        return;
      }
      final nonWebNative =
          upstreamError == null && _isNonWebNativeFormat(widget.name);
      setState(() {
        _loading = false;
        _isUnsupportedFormat = nonWebNative;
        _errorMessage = switch ((upstreamError, nonWebNative)) {
          (final MediaUpstreamException error, _) => error.userMessage,
          (_, true) => Errors.unsupportedVideoFormat(_extensionOf(widget.name)),
          _ => Errors.unplayableMedia,
        };
      });
      return;
    }

    if (!mounted) {
      await controller.dispose();
      await proxy?.close();
      return;
    }

    setState(() {
      _controller = controller;
      _proxy = proxy;
      _loading = false;
    });

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
    try {
      // The media URL carries the file's path and serial as query
      // parameters; its own path is the download endpoint, not the file.
      final params = widget.url.queryParameters;
      await FilesService.saveFile(
        params['filePath'] ?? '',
        serial: params['serial'],
        fileName: widget.name,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'download the video'))),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _enterTrimMode() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    controller.pause();
    setState(() {
      _trimMode = true;
      _trimStart = 0.0;
      _trimEnd = 1.0;
    });
  }

  Future<void> _exportTrim() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_exportingTrim) return;

    final params = widget.url.queryParameters;
    final relPath = params['filePath'] ?? '';
    final serial = params['serial'];
    if (relPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot trim: file path unknown')),
      );
      return;
    }

    final totalMs = controller.value.duration.inMilliseconds;
    final startMs = (_trimStart * totalMs).round();
    final endMs = (_trimEnd * totalMs).round();

    setState(() => _exportingTrim = true);
    try {
      final savedPath = await FilesService.trimVideo(
        relPath,
        serial: serial,
        startMs: startMs,
        endMs: endMs,
      );
      if (!mounted) return;
      final fileName = savedPath.split('/').last;
      setState(() {
        _trimMode = false;
        _trimStart = 0.0;
        _trimEnd = 1.0;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Clip saved as $fileName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'trim the video'))),
      );
    } finally {
      if (mounted) setState(() => _exportingTrim = false);
    }
  }

  Future<void> _saveFrame() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (_savingFrame) return;

    // Derive relPath and serial from the media URL query parameters.
    final params = widget.url.queryParameters;
    final relPath = params['filePath'] ?? '';
    final serial = params['serial'];
    if (relPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cannot save frame: file path unknown')),
      );
      return;
    }

    final wasPlaying = controller.value.isPlaying;
    if (wasPlaying) await controller.pause();

    final positionMs = controller.value.position.inMilliseconds;

    if (!mounted) return;
    setState(() => _savingFrame = true);
    try {
      final savedPath = await FilesService.extractVideoFrame(
        relPath,
        serial: serial,
        timestampMs: positionMs,
      );
      if (!mounted) return;
      final fileName = savedPath.split('/').last;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Frame saved as $fileName')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'save the frame'))),
      );
    } finally {
      if (mounted) setState(() => _savingFrame = false);
      if (wasPlaying && _controller != null) await _controller!.play();
    }
  }

  Future<void> _convert() async {
    final params = widget.url.queryParameters;
    final relPath = params['filePath'] ?? '';
    final fileName = relPath.split('/').last;
    final dot = fileName.lastIndexOf('.');
    final choice = await TranscodeDialogHost.show(
      context,
      loadFormats: FilesService.listTranscodeFormats,
      sourceFormat: dot <= 0 ? null : fileName.substring(dot + 1),
    );
    if (choice == null || !mounted) return;
    final (format, quality) = choice;
    try {
      await FilesService.transcodeVideo(
        relPath,
        serial: params['serial'],
        format: format,
        quality: quality.name,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Conversion started'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () {
              if (mounted) context.go(AppRoutes.jobs);
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(Errors.transcode(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      appBar: AppBar(
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
                  onPressed: _exportTrim,
                  child: const Text('Save Clip'),
                ),
                TextButton(
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
