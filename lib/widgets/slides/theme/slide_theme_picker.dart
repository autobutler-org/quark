import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/theme/slide_no_theme_note.dart';
import 'package:quark/widgets/slides/theme/slide_preview_card.dart';
import 'package:quark/widgets/slides/theme/slide_previews.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The theme picker (#1163): each of [themes] as a [SlidePreviewCard] of
/// the same sample slide drawn in it, the [current] one marked. A
/// presentation with no theme gets a [SlideNoThemeNote] above the cards,
/// whose button applies the first of [themes].
///
/// The cards wrap, so the picker fits the properties panel, a toolbar
/// menu and a phone's bottom sheet alike.
///
/// Key prefixes: `slide_theme_picker` on the picker, `slide_theme_<id>` on
/// each card, and the note's own.
class SlideThemePicker extends StatelessWidget {
  /// The picker over [themes], [current] marked.
  const SlideThemePicker({
    required this.themes,
    required this.current,
    required this.size,
    required this.onSelected,
    super.key,
  });

  /// The themes offered, in order.
  final List<SlideTheme> themes;

  /// The presentation's theme; null for none.
  final SlideTheme? current;

  /// The presentation's slide size, which the previews take.
  final SlideSize size;

  /// Applies a theme; null renders the picker disabled.
  final ValueChanged<SlideTheme>? onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onSelected = this.onSelected;
    final sample = SlidePreviews.themeSample(size);
    return Column(
      key: const ValueKey('slide_theme_picker'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tokens.spacingSm,
      children: [
        if (current == null && themes.isNotEmpty)
          SlideNoThemeNote(
            onApply: onSelected == null ? null : () => onSelected(themes.first),
          ),
        Wrap(
          spacing: tokens.spacingXs,
          runSpacing: tokens.spacingXs,
          children: [
            for (final theme in themes)
              SlidePreviewCard(
                key: ValueKey('slide_theme_${theme.id}'),
                slide: sample,
                size: size,
                theme: theme,
                label: theme.name,
                selected: theme.id == current?.id,
                onPressed: onSelected == null ? null : () => onSelected(theme),
              ),
          ],
        ),
      ],
    );
  }
}
