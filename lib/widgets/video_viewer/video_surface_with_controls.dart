import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quark/widgets/video_viewer/player_controls.dart';
import 'package:video_player/video_player.dart';

/// The video itself plus its overlaid controls, which fade out while playing
/// and come back on a tap.
class VideoSurfaceWithControls extends StatefulWidget {
  final VideoPlayerController controller;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;
  final Widget? topOverlay;

  /// The key of the `RepaintBoundary` around the video alone, without the
  /// controls, which Save Frame captures.
  final GlobalKey? frameKey;
  // Trim state passed down from the video viewer page.
  final bool trimMode;
  final double trimStart;
  final double trimEnd;
  final ValueChanged<double>? onTrimStartChanged;
  final ValueChanged<double>? onTrimEndChanged;

  const VideoSurfaceWithControls({
    super.key,
    required this.controller,
    required this.isFullscreen,
    required this.onToggleFullscreen,
    this.topOverlay,
    this.frameKey,
    this.trimMode = false,
    this.trimStart = 0.0,
    this.trimEnd = 1.0,
    this.onTrimStartChanged,
    this.onTrimEndChanged,
  });

  @override
  State<VideoSurfaceWithControls> createState() =>
      _VideoSurfaceWithControlsState();
}

class _VideoSurfaceWithControlsState extends State<VideoSurfaceWithControls> {
  static const Duration _hideDelay = Duration(seconds: 3);
  Timer? _hideTimer;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handlePlayerStateChanged);
    _scheduleHideIfPlaying();
  }

  @override
  void didUpdateWidget(covariant VideoSurfaceWithControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handlePlayerStateChanged);
      widget.controller.addListener(_handlePlayerStateChanged);
      _scheduleHideIfPlaying();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handlePlayerStateChanged);
    _cancelHideTimer();
    super.dispose();
  }

  void _handlePlayerStateChanged() {
    if (!mounted) {
      return;
    }
    if (widget.controller.value.isPlaying) {
      _scheduleHideIfPlaying();
      return;
    }

    _cancelHideTimer();
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
  }

  void _cancelHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = null;
  }

  void _scheduleHideIfPlaying() {
    _cancelHideTimer();
    if (!widget.controller.value.isPlaying) {
      return;
    }
    _hideTimer = Timer(_hideDelay, () {
      if (!mounted || !widget.controller.value.isPlaying) {
        return;
      }
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _onSurfaceTap() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
    if (_controlsVisible) {
      _scheduleHideIfPlaying();
    } else {
      _cancelHideTimer();
    }
  }

  void _onControlsInteraction() {
    if (!_controlsVisible) {
      setState(() {
        _controlsVisible = true;
      });
    }
    _scheduleHideIfPlaying();
  }

  double _safeAspectRatio(double raw) {
    if (!raw.isFinite || raw <= 0) {
      return 16 / 9;
    }
    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final ratio = _safeAspectRatio(widget.controller.value.aspectRatio);

    return ColoredBox(
      color: Colors.black,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: ratio,
              child: RepaintBoundary(
                key: widget.frameKey,
                child: VideoPlayer(widget.controller),
              ),
            ),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _onSurfaceTap,
              child: const SizedBox.expand(),
            ),
          ),
          if (widget.topOverlay != null)
            AnimatedOpacity(
              opacity: _controlsVisible ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: widget.topOverlay,
              ),
            ),
          AnimatedOpacity(
            opacity: _controlsVisible ? 1 : 0,
            duration: const Duration(milliseconds: 180),
            child: IgnorePointer(
              ignoring: !_controlsVisible,
              child: PlayerControls(
                controller: widget.controller,
                isFullscreen: widget.isFullscreen,
                onToggleFullscreen: () {
                  _onControlsInteraction();
                  widget.onToggleFullscreen();
                },
                onInteraction: _onControlsInteraction,
                trimMode: widget.trimMode,
                trimStart: widget.trimStart,
                trimEnd: widget.trimEnd,
                onTrimStartChanged: widget.onTrimStartChanged,
                onTrimEndChanged: widget.onTrimEndChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
