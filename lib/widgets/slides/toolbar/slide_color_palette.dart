import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/toolbar/slide_hex_field.dart';
import 'package:quark/widgets/slides/toolbar/slide_swatch_button.dart';
import 'package:quark/widgets/slides/toolbar/slide_swatches.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar_choice.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The colors a slide color control offers: the none option, the
/// token-derived [slideSwatches], and a [SlideHexField] for any other
/// color. Each pick goes to [choice]'s `onChanged`, one undo step.
///
/// The swatches wrap, so the palette fits a phone's menu and the properties
/// panel alike.
///
/// Key prefixes: `<choice.key>_none`, `<choice.key>_<index>` by swatch
/// index, and `<choice.key>_hex` on the field.
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
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingSm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              children: [
                SlideSwatchButton(
                  key: ValueKey('${choice.key}_none'),
                  name: choice.noneLabel,
                  color: null,
                  selected: false,
                  onPressed: onChanged == null ? null : () => onChanged(null),
                ),
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
              color: current,
              label: '${choice.label} (hex)',
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
