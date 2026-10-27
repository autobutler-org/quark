import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/media_autoplay.dart';
import 'package:quark/utils/music_play_threshold.dart';
import 'package:quark/widgets/audio_player/audio_controls.dart';
import 'package:quark/widgets/audio_player/error_view.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:video_player/video_player.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Full-screen player for an audio file on the Quark.
///
/// Once the listening crosses [MusicPlayThreshold] it counts one play in the
/// user's music history (#3284), at most once per opening. A file the
/// library does not know is answered 404 and nothing is counted.
class AudioPlayerPage extends StatefulWidget {
  final Uri url;
  final String name;

  /// Counts a play of the file at a path on a device; tests pass a fake.
  final Future<void> Function(String relPath, {String serial}) recordPlay;

  /// Whether playback may start without the user pressing play.
  final bool Function() canAutoplay;

  /// Closes the player from its back button. Null leaves the app bar's own,
  /// which pops the route this player was pushed on.
  final VoidCallback? onClose;

  const AudioPlayerPage({
    super.key,
    required this.url,
    required this.name,
    this.canAutoplay = canAutoplayMedia,
    this.onClose,
    this.recordPlay = MusicService.recordPlay,
  });

  @override
  State<AudioPlayerPage> createState() => _AudioPlayerPageState();
}

class _AudioPlayerPageState extends State<AudioPlayerPage> {
  VideoPlayerController? _controller;
  LocalMediaProxy? _proxy;
  bool _loading = true;
  String? _errorMessage;
  bool _downloading = false;
  MusicPlayThreshold? _playThreshold;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    VideoPlayerController? controller;
    LocalMediaProxy? proxy;
    try {
      // A quark on the local network serves a self-signed cert that the
      // native player refuses. Route through a loopback proxy that terminates
      // TLS in Dart, where the app's trust exception applies.
      if (mediaNeedsLocalProxy(widget.url)) {
        proxy = await LocalMediaProxy.start(widget.url);
      }
      controller = VideoPlayerController.networkUrl(
        proxy?.localUrl ?? widget.url,
      );
      await controller.initialize();
    } catch (e) {
      debugPrint('[audio_player_page.dart] initialize error: $e');
      await controller?.dispose();
      // If the server answered 404 or 401, say that. Blaming the codec sends
      // the user off re-encoding a file that was never the problem.
      final upstreamError = proxy?.lastUpstreamError;
      await proxy?.close();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            upstreamError?.userMessage ?? Errors.unsupportedAudioFormat;
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
    _playThreshold = MusicPlayThreshold(controller.value.duration);
    controller.addListener(_countPlay);

    // A play() the browser blocks for lack of a user gesture does not throw;
    // it leaves the controller in an error state where play does nothing
    // (#2002). Start playback only when the browser will allow it.
    if (widget.canAutoplay()) {
      try {
        await controller.play();
      } catch (_) {
        // A native player that refuses to start leaves the audio paused.
      }
    }
  }

  /// Posts the play once the listening crosses the threshold. A failure is
  /// only logged: the history is a nicety, and the song keeps playing.
  void _countPlay() {
    final controller = _controller;
    final relPath = widget.url.queryParameters['filePath'];
    if (controller == null || relPath == null || relPath.isEmpty) return;
    if (!(_playThreshold?.update(controller.value.position) ?? false)) return;
    widget
        .recordPlay(relPath, serial: widget.url.queryParameters['serial'] ?? '')
        .catchError(
          (Object e) => debugPrint('[audio_player_page.dart] record play: $e'),
        );
  }

  @override
  void dispose() {
    _controller?.removeListener(_countPlay);
    _controller?.dispose();
    _controller = null;
    _proxy?.close();
    _proxy = null;
    super.dispose();
  }

  Future<void> _download() async {
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

  @override
  Widget build(BuildContext context) {
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
              QuarkBarIconButton(
                key: const ValueKey('audio_player_download'),
                icon: QuarkIcons.download_outlined,
                tooltip: 'Download',
                isBusy: _downloading,
                onPressed: _download,
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
            ? ErrorView(
                message: _errorMessage!,
                onDownload: _download,
                downloading: _downloading,
              )
            : _controller != null
            ? AudioControls(controller: _controller!)
            : const SizedBox.shrink(),
      ),
    );
  }
}
