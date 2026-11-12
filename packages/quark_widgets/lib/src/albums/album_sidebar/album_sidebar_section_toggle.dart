import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';
import '../../theme/reduce_motion.dart';

/// The "Albums" label in an `AlbumSidebar` header, which doubles as the
/// button that folds the whole section away and opens it again.
///
/// Give it [onToggle] and the label gains a chevron, a tooltip, and an
/// expanded or collapsed state a screen reader announces; it takes focus and
/// answers Enter and Space like any button. Without [onToggle] it is the
/// plain label.
///
/// The chevron turns between the two states, and snaps under reduced motion.
///
/// Key prefixes: `album_section_toggle` on the button.
///
/// ```dart
/// AlbumSidebarSectionToggle(
///   isExpanded: controller.albumsSectionExpanded,
///   onToggle: controller.toggleAlbumsSectionExpanded,
/// );
/// ```
class AlbumSidebarSectionToggle extends StatelessWidget {
  /// Creates the label, a button when [onToggle] is given.
  const AlbumSidebarSectionToggle({
    required this.isExpanded,
    required this.onToggle,
    super.key,
  });

  /// Whether the section's list is showing.
  final bool isExpanded;

  /// Called when the label is tapped or activated from the keyboard. Null
  /// renders the plain label with no chevron.
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final onToggle = this.onToggle;
    final color = colorScheme.onSurface.withValues(alpha: 0.5);
    final label = Text(
      'Albums',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.8,
      ),
    );
    if (onToggle == null) return label;

    // A Material button, like the sort and create buttons beside it, so its
    // tap target follows the theme's density the way theirs do and the
    // header stays one height. The tooltip sits inside the MergeSemantics so
    // its text joins the button's node; above it, the tooltip's semantics have
    // no node of their own and land on whatever ancestor has one, which on the
    // Photos page is the page itself (#3642).
    return MergeSemantics(
      child: Semantics(
        expanded: isExpanded,
        child: Tooltip(
          message: isExpanded ? 'Collapse albums' : 'Expand albums',
          child: TextButton(
            key: const ValueKey('album_section_toggle'),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(24, 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(tokens.radiusSm),
              ),
            ),
            onPressed: onToggle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                label,
                SizedBox(width: tokens.spacingXs),
                AnimatedRotation(
                  turns: isExpanded ? 0 : -0.25,
                  duration: reduceMotionOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 150),
                  child: Icon(QuarkIcons.expand_more, size: 16, color: color),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
