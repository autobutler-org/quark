import 'package:flutter/widgets.dart';

/// Steps Day, Week or Month one span back or forward when [child] is swiped
/// sideways: right for [onPrevious], left for [onNext].
///
/// A swipe counts once it has traveled [distance] or is let go faster than
/// [velocity], and goes the way it traveled. Speed alone would miss a mouse
/// drag, which usually comes to rest before the button is released and so
/// ends with no fling at all (#2885); a short, slow drag steps nowhere.
///
/// It is stateful only for where the drag began.
class CalendarSwipeDetector extends StatefulWidget {
  /// Wraps [child] in the swipe.
  const CalendarSwipeDetector({
    required this.onPrevious,
    required this.onNext,
    required this.child,
    super.key,
  });

  /// Steps one span back: a swipe to the right.
  final VoidCallback onPrevious;

  /// Steps one span forward: a swipe to the left.
  final VoidCallback onNext;

  /// What is swiped.
  final Widget child;

  /// How far a drag has to go to step, in logical pixels.
  static const double distance = 64;

  /// How fast a shorter fling has to be to step, in logical pixels a second.
  static const double velocity = 300;

  @override
  State<CalendarSwipeDetector> createState() => _CalendarSwipeDetectorState();
}

class _CalendarSwipeDetectorState extends State<CalendarSwipeDetector> {
  double _startX = 0;

  void _end(DragEndDetails details) {
    final traveled = details.globalPosition.dx - _startX;
    final fling = details.primaryVelocity ?? 0;
    final way = traveled.abs() >= CalendarSwipeDetector.distance
        ? traveled
        : (fling.abs() > CalendarSwipeDetector.velocity ? fling : 0);
    if (way > 0) widget.onPrevious();
    if (way < 0) widget.onNext();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onHorizontalDragStart: (details) => _startX = details.globalPosition.dx,
    onHorizontalDragEnd: _end,
    child: widget.child,
  );
}
