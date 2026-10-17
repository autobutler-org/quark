import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:quark/utils/image_viewer_config.dart';

/// Page physics for the photo viewer that turns the page on a short swipe.
///
/// [PageScrollPhysics] turns the page on any fling, but a drag that ends with
/// the finger at rest has no velocity, and then it settles on whichever page is
/// nearer — so a thumb swipe that slowed before lifting needed to cross half
/// the screen (#3358). These physics turn the page once that swipe has carried
/// it [ImageViewerConfig.pageTurnFraction] of the way, in the direction the
/// finger last moved. A fling still turns it the way [PageScrollPhysics] does.
///
/// For a [PageView] with `pageSnapping: false` and a viewport fraction of 1:
/// with snapping on, the view wraps these in its own [PageScrollPhysics],
/// which would decide every settle before these are asked.
class PhotoPageScrollPhysics extends PageScrollPhysics {
  /// Creates the physics, over [parent].
  const PhotoPageScrollPhysics({super.parent});

  @override
  PhotoPageScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      PhotoPageScrollPhysics(parent: buildParent(ancestor));

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final tolerance = toleranceFor(position);
    if (velocity.abs() > tolerance.velocity ||
        position is! ScrollPosition ||
        position.outOfRange) {
      return super.createBallisticSimulation(position, velocity);
    }
    final page = position.pixels / position.viewportDimension;
    final progress = page - page.floorToDouble();
    // The finger moving toward the start scrolls forward, which carries the
    // view back a page.
    final double? targetPage = switch (position.userScrollDirection) {
      ScrollDirection.reverse
          when progress > ImageViewerConfig.pageTurnFraction =>
        page.ceilToDouble(),
      ScrollDirection.forward
          when progress > 0 &&
              progress < 1 - ImageViewerConfig.pageTurnFraction =>
        page.floorToDouble(),
      _ => null,
    };
    if (targetPage == null) {
      return super.createBallisticSimulation(position, velocity);
    }
    return ScrollSpringSimulation(
      spring,
      position.pixels,
      (targetPage * position.viewportDimension).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      ),
      velocity,
      tolerance: tolerance,
    );
  }
}
