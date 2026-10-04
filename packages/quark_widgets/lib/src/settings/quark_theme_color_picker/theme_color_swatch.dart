import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../theme/quark_tokens.dart';

/// One round swatch in a `QuarkThemeColorPicker`: a 28px disc of the theme's
/// chrome color with a dot of its accent in the middle, in a 48dp target.
///
/// It is ringed and its dot checked when [selected], so the choice does not
/// rest on color alone, and it is named by [label] in a tooltip and to a
/// screen reader. The parent gives it its key.
class ThemeColorSwatch extends StatelessWidget {
  /// Creates a swatch of [chrome] with a dot of [accent].
  const ThemeColorSwatch({
    required this.chrome,
    required this.accent,
    required this.checkColor,
    required this.label,
    required this.selected,
    required this.onTap,
    super.key,
  });

  /// The disc: the theme's chrome color for the brightness on screen.
  final Color chrome;

  /// The dot: the theme's accent for the brightness on screen.
  final Color accent;

  /// The color of the check drawn on [accent] when [selected].
  final Color checkColor;

  /// The theme color's name, shown on hover and read by a screen reader.
  final String label;

  /// Whether this is the theme color in use.
  final bool selected;

  /// Called when the swatch is tapped.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Semantics(
      label: label,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      button: true,
      excludeSemantics: true,
      // Excluding the child's semantics drops its tap too, so the node
      // carries its own, or a screen reader cannot press it (#2603).
      onTap: onTap,
      child: Tooltip(
        message: label,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          child: SizedBox.square(
            dimension: kMinInteractiveDimension,
            child: Center(
              child: Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: chrome,
                  shape: BoxShape.circle,
                  // Classic chrome is nearly the color of the card it sits on.
                  border: Border.all(color: tokens.border),
                  boxShadow: selected
                      ? [
                          BoxShadow(color: tokens.card, spreadRadius: 2),
                          BoxShadow(color: tokens.foreground, spreadRadius: 4),
                        ]
                      : null,
                ),
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: accent,
                    shape: BoxShape.circle,
                  ),
                  child: selected
                      ? Icon(
                          QuarkIcons.check_rounded,
                          size: 12,
                          color: checkColor,
                        )
                      : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
