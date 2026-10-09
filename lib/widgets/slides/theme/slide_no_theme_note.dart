import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the theme picker says over its cards for a presentation with no
/// theme (#1163). `SlidesService` gives every deck it creates or opens one
/// (#2867), so this covers a deck whose theme was taken off: it is drawn in
/// the light theme's colors and keeps working, and [onApply] gives it a
/// theme in one step.
///
/// Key prefixes: `slide_theme_none` on the note, `slide_theme_apply` on its
/// button.
class SlideNoThemeNote extends StatelessWidget {
  /// The note, whose button calls [onApply].
  const SlideNoThemeNote({required this.onApply, super.key});

  /// Applies a theme; null renders the button disabled.
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      key: const ValueKey('slide_theme_none'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: tokens.spacingXs,
      children: [
        Text('No theme', style: text.titleSmall),
        Text(
          'This presentation uses the default colors. Apply a theme to '
          'restyle every slide at once.',
          style: text.bodySmall?.copyWith(color: tokens.mutedForeground),
        ),
        FilledButton.tonalIcon(
          key: const ValueKey('slide_theme_apply'),
          onPressed: onApply,
          icon: const Icon(QuarkIcons.slide_theme),
          label: const Text('Apply a theme'),
        ),
      ],
    );
  }
}
