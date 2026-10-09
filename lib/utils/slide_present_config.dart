/// Tuning for present mode's swipe between slides (#2936).
///
/// A swipe counts once it has traveled [swipeDistance] or is let go faster
/// than [swipeVelocity]. Speed alone missed a slow, deliberate drag and a
/// mouse drag that comes to rest before the button is released; distance
/// alone would miss a short flick. The numbers match the calendar's swipe
/// (#2885), so a gesture that steps one steps the other.
abstract final class SlidePresentConfig {
  /// How far a drag has to go to step, in logical pixels.
  ///
  /// Well past the touch slop that turns a press into a drag, so a finger
  /// that wanders while tapping steps nowhere.
  static const double swipeDistance = 64;

  /// How fast a shorter fling has to be to step, in logical pixels a second.
  static const double swipeVelocity = 300;
}
