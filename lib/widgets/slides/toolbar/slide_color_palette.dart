import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_hex_field.dart';
import 'package:quark/widgets/slides/toolbar/slide_swatch_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_swatches.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The colors a slide color control offers: the none option and the
/// presentation's theme colors ([themeSwatches], #1163) first, then the
/// token-derived [slideSwatches], and a [SlideHexField] for any other
/// color. Each pick goes to [choice]'s `onChanged`, one undo step.
///
/// A theme swatch writes the role, not its value, so the color follows
/// the deck when its theme changes; it is drawn in [choice]'s theme, or in
/// [SlideThemes.light] for a deck with none, which is how the canvas draws
/// it too. The hex field shows a role color's value in that theme.
///
/// The swatches wrap, so the palette fits a phone's menu and the properties
/// panel alike.
///
/// Key prefixes: `<choice.key>_none`, `<choice.key>_theme_<role>` by
/// theme role, `<choice.key>_<index>` by swatch index, and
/// `<choice.key>_hex` on the field.
class SlideColorPalette extends StatelessWidget {
  /// The palette for [choice].
  const SlideColorPalette({required this.choice, this.width = 240, super.key});

  /// The color control the palette sets.
  final SlideColorChoice choice;

  /// How wide the palette is laid out.
  final double width;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onChanged = choice.onChanged;
    final current = choice.current;
    final theme = choice.theme ?? SlideThemes.light;
    final caption = Theme.of(
      context,
    ).textTheme.labelSmall?.copyWith(color: tokens.mutedForeground);
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingSm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Theme colors', style: caption),
            Wrap(
              children: [
                SlideSwatchButton(
                  key: ValueKey('${choice.key}_none'),
                  name: choice.noneLabel,
                  color: null,
                  selected: false,
                  onPressed: onChanged == null ? null : () => onChanged(null),
                ),
                for (final swatch in themeSwatches())
                  SlideSwatchButton(
                    key: ValueKey(
                      '${choice.key}_theme_${swatch.color.role!.name}',
                    ),
                    name: swatch.name,
                    color: Color(swatch.color.resolve(theme)),
                    selected: current == swatch.color,
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged(swatch.color),
                  ),
              ],
            ),
            Text('More colors', style: caption),
            Wrap(
              children: [
                for (final (i, swatch) in slideSwatches(tokens).indexed)
                  SlideSwatchButton(
                    key: ValueKey('${choice.key}_$i'),
                    name: swatch.name,
                    color: Color(swatch.color.argb),
                    selected: current == swatch.color,
                    onPressed: onChanged == null
                        ? null
                        : () => onChanged(swatch.color),
                  ),
              ],
            ),
            SizedBox(height: tokens.spacingSm),
            SlideHexField(
              key: ValueKey('${choice.key}_hex'),
              color: current == null || !current.isThemeColor
                  ? current
                  : SlideColor(current.resolve(theme)),
              label: '${choice.label} (hex)',
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
