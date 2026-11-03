import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quark/widgets/image_viewer/shortcut_row.dart';
import 'package:quark/widgets/video_viewer/player_controls.dart';
import 'package:video_player/video_player.dart';

/// The video itself plus its overlaid controls, which fade out while playing
/// and come back on a tap.
///
/// Keyboard: Space plays and pauses, ← and → skip back and forward ten
/// seconds, and ? lists those shortcuts.
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
  static const Duration _skip = Duration(seconds: 10);
  final FocusNode _focusNode = FocusNode(debugLabel: 'VideoSurface');
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
    _focusNode.dispose();
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

  KeyEventResult _handleKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    // "?" arrives as the question key, or as slash with the character "?"
    // (US Shift+/).
    if (event.logicalKey == LogicalKeyboardKey.question ||
        event.character == '?') {
      // A held ? would otherwise stack the dialog.
      if (event is KeyDownEvent) _showShortcuts();
      _onControlsInteraction();
      return KeyEventResult.handled;
    }
    final controller = widget.controller;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.space:
        // A held Space would otherwise flicker between play and pause.
        if (event is KeyRepeatEvent) return KeyEventResult.handled;
        controller.value.isPlaying ? controller.pause() : controller.play();
      case LogicalKeyboardKey.arrowLeft:
        controller.seekTo(controller.value.position - _skip);
      case LogicalKeyboardKey.arrowRight:
        controller.seekTo(controller.value.position + _skip);
      default:
        return KeyEventResult.ignored;
    }
    _onControlsInteraction();
    return KeyEventResult.handled;
  }

  /// The same short list the image viewer opens on ?, for the keys this
  /// surface actually handles.
  void _showShortcuts() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('video_shortcuts_dialog'),
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Keyboard shortcuts',
          style: TextStyle(color: Colors.white),
        ),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ShortcutRow(shortcut: 'Space', description: 'Play / Pause'),
              ShortcutRow(shortcut: '←', description: 'Back 10 seconds'),
              ShortcutRow(shortcut: '→', description: 'Forward 10 seconds'),
              ShortcutRow(shortcut: '?', description: 'Show this help'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  void _onSurfaceTap() {
    _focusNode.requestFocus();
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

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKey,
      child: ColoredBox(
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
      ),
    );
  }
}
