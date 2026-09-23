import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/media_autoplay.dart';
import 'package:quark/widgets/audio_player/audio_controls.dart';
import 'package:quark/widgets/audio_player/error_view.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:video_player/video_player.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Full-screen player for an audio file on the Quark.
class AudioPlayerPage extends StatefulWidget {
  final Uri url;
  final String name;

  /// Whether playback may start without the user pressing play.
  final bool Function() canAutoplay;

  const AudioPlayerPage({
    super.key,
    required this.url,
    required this.name,
    this.canAutoplay = canAutoplayMedia,
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

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    _proxy?.close();
    _proxy = null;
    super.dispose();
  }

  Future<void> _download() async {
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
        SnackBar(content: Text(Errors.message(e, 'download the file'))),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
