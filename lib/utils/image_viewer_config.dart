/// Tuning for photo caching, prefetching, decoding and gestures in the image
/// viewer (#1710, #3358).
///
/// Gathered here rather than spread through the viewer and its cache because
/// every one of these numbers is a tradeoff someone will want to revisit, and
/// the reasoning belongs next to the value rather than in the commit that
/// changed it.
abstract final class ImageViewerConfig {
  /// Total encoded bytes the photo cache may hold before it evicts.
  ///
  /// Encoded, never decoded: a 4000x3000 photo is a few megabytes as JPEG and
  /// ~48MB as raw RGBA, so a budget that is comfortable for one is an OOM kill
  /// for the other. At the 3-8MB a phone photo typically runs, 64MiB holds
  /// somewhere between eight and twenty of them — far more than the handful a
  /// user browses back and forth across, and small enough to sit inside a
  /// low-end device's budget alongside the decoded frame on screen.
  static const int photoCacheBudgetBytes = 64 * 1024 * 1024;

  /// How many photos either side of the current one are fetched in the
  /// background.
  ///
  /// One. The next action is almost always the next or previous photo, and
  /// every step past that spends a stranger's cellular data on a photo they
  /// may never reach. Swiping faster than one photo per download costs nothing
  /// either: navigations coalesce, and the bytes a superseded one downloaded
  /// still land in the cache, so a fast swipe warms everything it passes.
  static const int prefetchWindow = 1;

  /// Zoom scale above which the photo counts as magnified.
  ///
  /// One threshold covers both things that care: the page physics has to stop
  /// scrolling so a drag pans instead of turning the page, and the downscaled
  /// decode has to give way to the full-resolution one before anything looks
  /// soft.
  ///
  /// Just above 1.0 rather than exactly 1.0, because `InteractiveViewer` is
  /// given no snap-back — a pinch that ends near 1x settles wherever the
  /// fingers left it, which is rarely 1.0 to the last bit. On exactly 1.0 a
  /// residual 1.0000001 would read as magnified forever, pinning the page
  /// physics and killing the swipe the viewer just gained (#1707). The 1%
  /// band this trades away is magnification no one can see.
  static const double zoomedInScale = 1.01;

  /// How far across the screen a swipe has to carry the photo to turn the
  /// page when the finger comes to rest before it lifts.
  ///
  /// A flick turns the page on its speed alone. A thumb swipe often slows to a
  /// stop before it lifts, and then has no speed left to read; page physics
  /// alone would then settle on whichever page is nearer, which takes a drag
  /// past half the screen. A quarter is a deliberate swipe on any phone, and
  /// still far more than the jitter of a tap or a vertical swipe (#3358).
  static const double pageTurnFraction = 0.25;

  /// How far down a drag has to pull the photo to close the viewer once the
  /// finger rests.
  static const double dismissDragDistance = 120;

  /// Downward speed, in logical pixels a second, that closes the viewer
  /// whatever the distance: a flick down.
  static const double dismissFlingVelocity = 700;

  /// The magnification a double-tap zooms to, around the point tapped.
  ///
  /// Comfortably inside the `InteractiveViewer`'s default 2.5x ceiling, so a
  /// pinch can still go further from there.
  static const double doubleTapZoomScale = 2;
}
