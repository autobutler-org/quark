import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Where a sectioned `PhotoGrid` reports which section sits at the top of the
/// viewport, for the `PhotoGridScrollLabel` above it to show.
///
/// The grid records each section's scroll offset while it lays out, which
/// happens every scroll frame, and the tracker settles on a label once the
/// frame is done, so a listener never rebuilds in the middle of layout.
class PhotoGridSectionTracker {
  /// The label of the section at the top of the viewport, or null before a
  /// sectioned grid has laid out.
  final ValueNotifier<String?> label = ValueNotifier(null);

  /// The scroll view the grid sits in, so the label can ignore every other
  /// scrollable under it, such as a sidebar's list.
  ScrollableState? scrollable;

  List<String> _labels = const [];
  List<double> _offsets = const [];
  bool _scheduled = false;

  /// Starts over with [labels], one per section in grid order.
  void setSections(List<String> labels) {
    if (listEquals(labels, _labels)) return;
    _labels = labels;
    _offsets = List.filled(labels.length, 0);
  }

  /// Records how far section [index]'s leading edge has scrolled past the top
  /// of the viewport: zero while it is still below.
  void observe(int index, double scrollOffset) {
    if (index >= _offsets.length) return;
    _offsets[index] = scrollOffset;
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      label.value = _current();
    });
  }

  /// Releases the label's listeners.
  void dispose() => label.dispose();

  String? _current() {
    if (_labels.isEmpty) return null;
    // Every section above the top has scrolled past it; the last of them is
    // the one the top of the viewport is in.
    var current = 0;
    for (var i = 0; i < _offsets.length; i++) {
      if (_offsets[i] > 0) current = i;
    }
    return _labels[current];
  }
}

/// Hands a [PhotoGridSectionTracker] down to the `PhotoGrid` inside a
/// `PhotoGridScrollLabel`.
///
/// ```dart
/// PhotoGridScrollLabelScope(tracker: tracker, child: scrollView);
/// ```
class PhotoGridScrollLabelScope extends InheritedWidget {
  /// Creates the scope over [child].
  const PhotoGridScrollLabelScope({
    required this.tracker,
    required super.child,
    super.key,
  });

  /// Where the grid reports.
  final PhotoGridSectionTracker tracker;

  /// The tracker of the nearest scope above [context], or null outside one.
  /// Reads without subscribing: the tracker never changes for a scope.
  static PhotoGridSectionTracker? maybeOf(BuildContext context) => context
      .getInheritedWidgetOfExactType<PhotoGridScrollLabelScope>()
      ?.tracker;

  @override
  bool updateShouldNotify(PhotoGridScrollLabelScope oldWidget) =>
      tracker != oldWidget.tracker;
}
