import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/widgets/video_viewer/video_surface_with_controls.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:video_player/video_player.dart';

/// The video surface on a route of its own, landscape and immersive.
class FullscreenVideoPage extends StatefulWidget {
  final VideoPlayerController controller;

  const FullscreenVideoPage({super.key, required this.controller});

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> {
  @override
  void initState() {
    super.initState();
    _enterFullscreenMode();
  }

  Future<void> _enterFullscreenMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _exitFullscreenMode() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    _exitFullscreenMode();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: Colors.black,
      body: VideoSurfaceWithControls(
        controller: widget.controller,
        isFullscreen: true,
        onToggleFullscreen: () => Navigator.of(context).pop(),
        topOverlay: Padding(
          padding: EdgeInsets.only(top: topInset + 8, left: 8),
          child: Align(
            alignment: Alignment.topLeft,
            child: IconButton(
              tooltip: 'Exit fullscreen',
              icon: const Icon(QuarkIcons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ),
      ),
    );
  }
}
