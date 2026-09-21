import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/local_media_proxy.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/audio_player/audio_controls.dart';
import 'package:quark/widgets/audio_player/error_view.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:video_player/video_player.dart';

/// Full-screen player for an audio file on the Quark.
class AudioPlayerPage extends StatefulWidget {
  final Uri url;
  final String name;

  const AudioPlayerPage({super.key, required this.url, required this.name});

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

    try {
      await controller.play();
    } catch (_) {}
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
          IconButton(
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded),
            tooltip: 'Download',
          ),
          const AppThemeToggle(),
        ],
      ),
      body: Center(
        child: _loading
            ? const CircularProgressIndicator()
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
