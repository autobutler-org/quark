import 'dart:async';

import 'package:flutter/material.dart';

import '../core/reduce_motion.dart';
import '../theme/quark_tokens.dart';
import 'photo_grid_scroll_label/photo_grid_scroll_label_pill.dart';
import 'photo_grid_scroll_label/photo_grid_scroll_label_scope.dart';

/// Floats the label of the section in view, such as "March 2025", over a
/// sectioned `PhotoGrid` while it scrolls, and fades it out once scrolling
/// has stopped for [hideAfter].
///
/// Wrap the scroll view holding the grid, or anything above it such as a
/// `QuarkSplitView`. The grid finds this widget on its own and reports which
/// section is at the top, so nothing has to be wired through the caller. Only
/// the grid's own scroll view shows the label; a sidebar list scrolling
/// under the same widget does not. A grid without sections never shows it.
///
/// The label is decorative, since the pinned section header says the same
/// thing, so it takes no pointer events and is left out of semantics. Under
/// reduced motion it appears and disappears without fading.
///
/// Key prefix: `photo_grid_scroll_label` on the label.
///
/// ```dart
/// PhotoGridScrollLabel(
///   child: CustomScrollView(
///     slivers: [PhotoGrid(photos: photos, sections: sections, ...)],
///   ),
/// );
/// ```
class PhotoGridScrollLabel extends StatefulWidget {
  /// Creates the label over [child].
  const PhotoGridScrollLabel({
    required this.child,
    this.hideAfter = const Duration(milliseconds: 1500),
    super.key,
  });

  /// The content holding the grid's scroll view.
  final Widget child;

  /// How long the label stays after the last scroll.
  final Duration hideAfter;

  @override
  State<PhotoGridScrollLabel> createState() => _PhotoGridScrollLabelState();
}

class _PhotoGridScrollLabelState extends State<PhotoGridScrollLabel>
    with WidgetsBindingObserver {
  static const _fade = Duration(milliseconds: 200);

  final _tracker = PhotoGridSectionTracker();
  Timer? _hide;
  bool _visible = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(_updateMotion);

  void _updateMotion() {
    _reduceMotion = reduceMotionOf(context);
  }

  bool _onScroll(ScrollUpdateNotification notification) {
    final grid = _tracker.scrollable;
    final from = notification.context;
    if (grid == null || from == null || Scrollable.maybeOf(from) != grid) {
      return false;
    }
    _hide?.cancel();
    _hide = Timer(widget.hideAfter, () {
      if (mounted) setState(() => _visible = false);
    });
    if (!_visible) setState(() => _visible = true);
    return false;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hide?.cancel();
    _tracker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Stack(
      children: [
        NotificationListener<ScrollUpdateNotification>(
          onNotification: _onScroll,
          child: PhotoGridScrollLabelScope(
            tracker: _tracker,
            child: widget.child,
          ),
        ),
        PositionedDirectional(
          top: 0,
          bottom: 0,
          end: tokens.spacingMd,
          child: IgnorePointer(
            child: ExcludeSemantics(
              child: Center(
                child: ValueListenableBuilder<String?>(
                  valueListenable: _tracker.label,
                  builder: (context, label, _) => AnimatedOpacity(
                    opacity: _visible && label != null ? 1 : 0,
                    duration: _reduceMotion ? Duration.zero : _fade,
                    child: label == null
                        ? const SizedBox.shrink()
                        : PhotoGridScrollLabelPill(label: label),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
