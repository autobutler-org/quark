import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quark/utils/image_viewer_config.dart';
import 'package:quark/widgets/image_viewer/photo_page_scroll_physics.dart';
import 'package:quark/widgets/image_viewer/single_finger_vertical_drag.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The swipeable photo surface, with the Live Photo badge and the gestures
/// that play a Live Photo, dismiss the mobile drawer, and close the viewer
/// on a swipe down.
///
/// A swipe sideways turns the page, a swipe down pulls the photo after the
/// finger and closes the viewer through [onSwipeDown] once it has gone far or
/// fast enough (#3358). Zoomed in, the caller passes no [onSwipeDown] and
/// [zoomedIn], and every drag pans the photo instead (#1707).
class PhotoArea extends StatefulWidget {
  /// The photo for [currentIndex]; every other page shows a spinner.
  final Widget currentPhoto;
  final PageController pageController;
  final int currentIndex;

  /// How many pages the view holds, loaded or not.
  final int imageCount;
  final ValueChanged<int> onPageChanged;
  final bool zoomedIn;
  final bool loading;
  final bool isLive;
  final bool liveVideoReady;
  final bool liveVideoPlaying;
  final VoidCallback onStartLivePlayback;
  final VoidCallback onStopLivePlayback;

  /// Tapping the photo closes the mobile drawer; null wherever a tap should
  /// do nothing.
  final VoidCallback? onTapDismissSidebar;

  /// Called when a swipe down asks to close the viewer; null turns the
  /// gesture off. Only one finger pulls: a second hands the gesture to the
  /// zoom's pinch. A mouse never drags it: on a desktop the photo is not
  /// something the pointer pulls around.
  final VoidCallback? onSwipeDown;

  const PhotoArea({
    super.key,
    required this.currentPhoto,
    required this.pageController,
    required this.currentIndex,
    required this.imageCount,
    required this.onPageChanged,
    required this.zoomedIn,
    required this.loading,
    required this.isLive,
    required this.liveVideoReady,
    required this.liveVideoPlaying,
    required this.onStartLivePlayback,
    required this.onStopLivePlayback,
    this.onTapDismissSidebar,
    this.onSwipeDown,
  });

  @override
  State<PhotoArea> createState() => _PhotoAreaState();
}

class _PhotoAreaState extends State<PhotoArea> {
  /// How far down the current swipe has pulled the photo.
  double _pull = 0;

  void _onPullUpdate(DragUpdateDetails details) =>
      setState(() => _pull = math.max(0, _pull + details.delta.dy));

  void _onPullEnd(DragEndDetails details) {
    final close =
        _pull >= ImageViewerConfig.dismissDragDistance ||
        (details.primaryVelocity ?? 0) >=
            ImageViewerConfig.dismissFlingVelocity;
    setState(() => _pull = 0);
    if (close) widget.onSwipeDown?.call();
  }

  @override
  Widget build(BuildContext context) {
    final onSwipeDown = widget.onSwipeDown;
    return RawGestureDetector(
      gestures: {
        if (onSwipeDown != null)
          SingleFingerVerticalDragGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<
                SingleFingerVerticalDragGestureRecognizer
              >(
                // Only a finger or a pen pulls the photo down.
                () => SingleFingerVerticalDragGestureRecognizer(
                  debugOwner: this,
                  supportedDevices: const {
                    PointerDeviceKind.touch,
                    PointerDeviceKind.stylus,
                    PointerDeviceKind.invertedStylus,
                    PointerDeviceKind.unknown,
                  },
                ),
                (drag) => drag
                  ..onUpdate = _onPullUpdate
                  ..onEnd = _onPullEnd
                  ..onCancel = () => setState(() => _pull = 0),
              ),
      },
      child: GestureDetector(
        onTap: widget.onTapDismissSidebar,
        onLongPressStart: widget.isLive && widget.liveVideoReady
            ? (_) => widget.onStartLivePlayback()
            : null,
        onLongPressEnd: widget.isLive && widget.liveVideoPlaying
            ? (_) => widget.onStopLivePlayback()
            : null,
        child: Transform.translate(
          offset: Offset(0, _pull),
          child: Stack(
            children: [
              // The viewer is index-based and only ever holds the bytes for
              // the photo on screen, so the pages the finger drags in from
              // show a spinner until _navigate has loaded them.
              PageView.builder(
                controller: widget.pageController,
                // The physics snap to a page themselves; see
                // PhotoPageScrollPhysics for why the view's own snapping is
                // off.
                pageSnapping: false,
                physics: widget.zoomedIn
                    ? const NeverScrollableScrollPhysics()
                    : const PhotoPageScrollPhysics(),
                itemCount: math.max(widget.imageCount, 1),
                onPageChanged: widget.onPageChanged,
                itemBuilder: (_, index) => Center(
                  child: index == widget.currentIndex
                      ? widget.currentPhoto
                      : const QuarkLoader(),
                ),
              ),
              if (widget.isLive && !widget.loading)
                Positioned(
                  top: 12,
                  left: 12,
                  child: LiveBadge(ready: widget.liveVideoReady),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
