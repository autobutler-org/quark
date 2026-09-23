import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The swipeable photo surface, with the Live Photo badge and the gestures
/// that play a Live Photo or dismiss the mobile drawer.
class PhotoArea extends StatelessWidget {
  /// The photo for [currentIndex]; every other page shows a spinner.
  final Widget currentPhoto;
  final PageController pageController;
  final int currentIndex;
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
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapDismissSidebar,
      onLongPressStart: isLive && liveVideoReady
          ? (_) => onStartLivePlayback()
          : null,
      onLongPressEnd: isLive && liveVideoPlaying
          ? (_) => onStopLivePlayback()
          : null,
      child: Stack(
        children: [
          // The viewer is index-based and only ever holds the bytes for the
          // photo on screen, so the pages the finger drags in from show a
          // spinner until _navigate has loaded them.
          PageView.builder(
            controller: pageController,
            physics: zoomedIn
                ? const NeverScrollableScrollPhysics()
                : const PageScrollPhysics(),
            itemCount: math.max(imageCount, 1),
            onPageChanged: onPageChanged,
            itemBuilder: (_, index) => Center(
              child: index == currentIndex ? currentPhoto : const QuarkLoader(),
            ),
          ),
          if (isLive && !loading)
            Positioned(
              top: 12,
              left: 12,
              child: LiveBadge(ready: liveVideoReady),
            ),
        ],
      ),
    );
  }
}
