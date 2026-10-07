import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One color in a slide color palette: a round swatch in a 48dp touch
/// target, outlined so white reads on a light card, with a check while it
/// is the color in use. A null [color] is the palette's "none" option,
/// drawn as an empty swatch struck through.
///
/// It reads to a screen reader as its [name], selected or not.
///
/// Key prefixes: none of its own; the palette passes `<key>_<index>`.
class SlideSwatchButton extends StatelessWidget {
  /// A swatch of [color] called [name].
  const SlideSwatchButton({
    required this.name,
    required this.color,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  /// What the color is called.
  final String name;

  /// The color; null for none.
  final Color? color;

  /// Whether it is the color in use.
  final bool selected;

  /// Picks the color; null renders it disabled.
  final VoidCallback? onPressed;

  /// The visible swatch's diameter.
  static const double swatchSize = 28;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final fill = color;
    // Light and dark text tokens, whichever reads on the swatch.
    final checkColor = fill == null || fill.computeLuminance() > 0.5
        ? QuarkTokens.light.foreground
        : QuarkTokens.dark.foreground;
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      excludeSemantics: true,
      child: Tooltip(
        message: name,
        child: InkResponse(
          onTap: onPressed,
          radius: 24,
          child: SizedBox.square(
            dimension: 48,
            child: Center(
              child: Container(
                width: swatchSize,
                height: swatchSize,
                decoration: BoxDecoration(
                  color: fill ?? tokens.card,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? tokens.primary : tokens.border,
                    width: selected ? 2 : 1,
                  ),
                ),
                child: fill == null
                    ? Icon(
                        QuarkIcons.close,
                        size: 18,
                        color: tokens.mutedForeground,
                      )
                    : selected
                    ? Icon(QuarkIcons.check, size: 18, color: checkColor)
                    : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
