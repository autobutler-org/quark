import 'package:material_ui/material_ui.dart';

import '../theme/quark_tokens.dart';

/// The centered state that takes over a panel with nothing to show: an icon,
/// a headline, optional supporting text, and an optional action.
///
/// Use it wherever a list, grid, or panel came back empty, could not load, or
/// is still waiting on something it cannot show yet. A failure passes the
/// sentence the app composed as [headline] and a retry as [action]; the
/// package never writes that sentence itself. Wrappers pass copy, an icon,
/// and an action, and never rebuild this column.
///
/// In a space too short for it, the block scrolls instead of overflowing.
///
/// Emits no `ValueKey`s of its own; the widget passed as [action] carries its
/// own key.
///
/// ```dart
/// EmptyStateWidget(
///   icon: QuarkIcons.folder,
///   headline: 'This folder is empty',
///   subtext: 'Upload a file to get started.',
///   action: FilledButton(onPressed: onUpload, child: const Text('Upload')),
/// );
/// ```
class EmptyStateWidget extends StatelessWidget {
  /// Creates an empty state headlined by [headline] under [icon].
  const EmptyStateWidget({
    required this.icon,
    required this.headline,
    this.subtext,
    this.action,
    super.key,
  });

  /// The glyph above the headline, sized to lead the block.
  final IconData icon;

  /// The one-line statement of what is missing. Sentence case, no period.
  final String headline;

  /// Optional supporting line under [headline], usually what to do next.
  final String? subtext;

  /// Optional call to action rendered below the text, usually a button.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);

    return Center(
      // Scrolls rather than overflows when whatever sits around it leaves less
      // height than the block needs, as a phone with a card over the listing
      // does (#2022). With room to spare it is as tall as its content, so the
      // Center still centers it.
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingXl,
          vertical: tokens.spacingLg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 56,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            SizedBox(height: tokens.spacingMd),
            Text(
              headline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            if (subtext != null) ...[
              SizedBox(height: tokens.spacingSm),
              Text(
                subtext!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                  height: 1.5,
                ),
              ),
            ],
            if (action != null) ...[
              SizedBox(height: tokens.spacingLg),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
