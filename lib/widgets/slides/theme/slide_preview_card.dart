import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_editor_canvas.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One choice in the theme or layout picker (#1163): [slide] drawn small by
/// a read-only [SlideCanvas] in [theme], named by [label] underneath,
/// outlined and checked while [selected].
///
/// The whole card is one button, at least 48dp tall, that reads to a
/// screen reader as [label], selected or not; the preview itself is not
/// read.
///
/// Key prefixes: none of its own; the picker passes `<prefix>_<id>`.
class SlidePreviewCard extends StatelessWidget {
  /// A card drawing [slide] at [size], called [label].
  const SlidePreviewCard({
    required this.slide,
    required this.size,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.theme,
    this.width = defaultWidth,
    super.key,
  });

  /// The slide to preview.
  final Slide slide;

  /// The presentation's slide size.
  final SlideSize size;

  /// What the card is called, under the preview.
  final String label;

  /// Whether this is the choice in use.
  final bool selected;

  /// Picks the choice; null renders it disabled.
  final VoidCallback? onPressed;

  /// The theme the preview is drawn in; null draws the canvas's fallback,
  /// the app's own colors.
  final SlideTheme? theme;

  /// How wide the card is.
  final double width;

  /// The width two cards side by side fit in a 280dp panel at.
  static const double defaultWidth = 116;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Semantics(
      button: true,
      selected: selected,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(tokens.radiusSm),
        child: SizedBox(
          width: width,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingXs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: tokens.spacingXs,
              children: [
                DecoratedBox(
                  position: DecorationPosition.foreground,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(tokens.radiusSm),
                    border: Border.all(
                      color: selected ? tokens.primary : tokens.border,
                      width: selected ? 3 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      RepaintBoundary(
                        child: SlideCanvas.readOnly(
                          slide: slide,
                          size: size,
                          theme: theme,
                          style: SlideEditorCanvas.styleOf(context),
                        ),
                      ),
                      if (selected)
                        PositionedDirectional(
                          top: tokens.spacingXs,
                          end: tokens.spacingXs,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: tokens.primary,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              QuarkIcons.check,
                              size: 16,
                              color: tokens.primaryForeground,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
