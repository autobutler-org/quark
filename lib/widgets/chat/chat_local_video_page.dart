import 'dart:io';

import 'package:flutter/material.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/video_viewer/fullscreen_video_page.dart';
import 'package:quark/widgets/video_viewer/inline_video_player.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:video_player/video_player.dart';

/// Plays a chat attachment that has already been decrypted to [path].
///
/// Uses the same surface as the file browser's video viewer. The caller
/// deletes [path] after this route pops.
class ChatLocalVideoPage extends StatefulWidget {
  /// Creates a player for the file at [path], titled [name].
  const ChatLocalVideoPage({required this.path, required this.name, super.key});

  /// Absolute path of the decrypted video.
  final String path;

  /// The file name shown in the title.
  final String name;

  @override
  State<ChatLocalVideoPage> createState() => _ChatLocalVideoPageState();
}

class _ChatLocalVideoPageState extends State<ChatLocalVideoPage> {
  VideoPlayerController? _controller;
  String? _error;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.file(File(widget.path));
    try {
      await controller.initialize();
      await controller.play();
    } catch (e) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _error = Errors.message(e, 'play the video'));
      return;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: _error != null
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(QuarkTokens.of(context).spacingMd),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : controller == null
          ? const Center(child: QuarkLoader())
          : Center(
              child: InlineVideoPlayer(
                controller: controller,
                onToggleFullscreen: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          FullscreenVideoPage(controller: controller),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
