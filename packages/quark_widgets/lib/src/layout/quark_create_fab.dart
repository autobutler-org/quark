import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/reduce_motion.dart';

/// The round `+` button a phone page floats in its bottom corner for its
/// main create action: Files' "Create" and Photos' "Upload" (#4150).
///
/// It fades out while the reader scrolls down a listing rather than
/// disappearing, so a scroll back up brings it straight back where it was,
/// and it ignores taps while faded. The page decides [visible], and
/// [visibleAfterScroll] is the rule both pages follow. Under reduced motion
/// it shows and hides without the fade.
///
/// Placing it is the page's: `QuarkPageScaffold.floatingActionButton` puts
/// it in the bottom right, or the bottom left when left-handed.
///
/// Key prefixes: none of its own. The caller's `key` sits on the button.
///
/// ```dart
/// QuarkCreateFab(
///   key: const ValueKey('photos_upload_fab'),
///   tooltip: 'Upload',
///   visible: fabVisible,
///   onPressed: upload,
/// );
/// ```
class QuarkCreateFab extends StatelessWidget {
  /// Creates the button, called [tooltip].
  const QuarkCreateFab({
    required this.visible,
    required this.onPressed,
    required this.tooltip,
    super.key,
  });

  /// Whether the button shows. False fades it out and lets taps through.
  final bool visible;

  /// Runs the page's create action.
  final VoidCallback onPressed;

  /// What the button does, such as "Create" or "Upload", shown on a long
  /// press and read by screen readers.
  final String tooltip;

  /// How far, in logical pixels, a scroll has to move before the button
  /// changes, so a jittery finger does not flicker it.
  static const double scrollSlop = 4;

  /// Whether the button should show after a listing scrolled by [delta] to
  /// [offset], given it is [visible] now: hidden going down, back going up,
  /// and always shown at the top.
  static bool visibleAfterScroll({
    required double offset,
    required double delta,
    required bool visible,
  }) {
    if (offset <= 0) return true;
    if (delta > scrollSlop) return false;
    if (delta < -scrollSlop) return true;
    return visible;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: visible ? 1.0 : 0.0,
      duration: reduceMotionOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: IgnorePointer(
        ignoring: !visible,
        child: FloatingActionButton(
          heroTag: 'create_fab',
          onPressed: onPressed,
          tooltip: tooltip,
          child: const Icon(QuarkIcons.add),
        ),
      ),
    );
  }
}
