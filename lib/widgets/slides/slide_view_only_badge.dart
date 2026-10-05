import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's bar indicator that the presentation is view only
/// (#1170): a lock and the words "View only", in place of the save chip,
/// because a reader's edits are never saved. Its tooltip, which a screen
/// reader announces too, says why.
///
/// Below [QuarkAppBarBottom.collapseBreakpoint] the bar has no room for the
/// words, so a phone sees the lock alone here and the words in the bar's
/// second row, after the slide position ([suffix]).
///
/// It is not a button: nothing happens when it is pressed.
///
/// Key prefixes: `slide_editor_view_only` on the indicator.
///
/// ```dart
/// if (controller.isReadOnly) const SlideViewOnlyBadge();
/// ```
class SlideViewOnlyBadge extends StatelessWidget {
  /// Creates the indicator.
  const SlideViewOnlyBadge({
    super.key = const ValueKey('slide_editor_view_only'),
  });

  /// The words the indicator shows.
  static const label = 'View only';

  /// What follows the slide position in the bar's second row, where a phone
  /// reads the words.
  static const suffix = ' · $label';

  /// What the tooltip tells the user.
  static const tooltip =
      'You can view this presentation but not change it. Ask the owner for '
      'edit access.';

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final compact =
        MediaQuery.sizeOf(context).width < QuarkAppBarBottom.collapseBreakpoint;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        container: true,
        label: '$label. $tooltip',
        excludeSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: kMinInteractiveDimension,
            minWidth: kMinInteractiveDimension,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingSm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: tokens.spacingXs,
              children: [
                Icon(
                  QuarkIcons.lock_outline,
                  size: 18,
                  color: tokens.mutedForeground,
                ),
                if (!compact)
                  Text(
                    label,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: tokens.mutedForeground,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
