import 'package:flutter/material.dart'
    show
        StatelessWidget,
        Widget,
        MouseCursor,
        BuildContext,
        Border,
        Color,
        EdgeInsets,
        Theme,
        BorderRadius,
        BoxDecoration,
        Container,
        MouseRegion;

/// Opacity of the primary-color tint over selected cells and headers.
const double kRangeTintAlpha = 0.12;

/// One grid cell's frame: its size, cursor, fill, and the borders that mark it as active, highlighted, or referenced
/// by the formula being edited.
///
/// A cell inside a multi-cell selection ([isInRange]) gets a tint of the
/// theme's primary color; the highlighted anchor keeps a plain fill so its outline
/// reads as the active cell.
class Cell extends StatelessWidget {
  final Widget child;
  final bool isActive;
  final bool isHighlighted;

  /// Whether the cell lies inside the selected range.
  final bool isInRange;
  final MouseCursor cursor;
  final double height;

  /// When non-null, this color is used as the cell border to indicate that
  /// the cell is referenced by the formula currently being edited.
  final Color? referenceColor;

  /// The cell's fill from its format, or null for none. The range tint and
  /// the active cell's color draw over it.
  final Color? fillColor;

  const Cell({
    super.key,
    required this.child,
    required this.isActive,
    required this.isHighlighted,
    this.isInRange = false,
    required this.cursor,
    this.height = 40,
    this.referenceColor,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: cursor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: referenceColor != null
              ? referenceColor!.withValues(alpha: 0.08)
              : isActive
                  ? cs.primaryContainer
                  : isInRange && !isHighlighted
                      ? Color.alphaBlend(
                          cs.primary.withValues(alpha: kRangeTintAlpha),
                          fillColor ?? const Color(0x00000000),
                        )
                      : fillColor,
          border: referenceColor != null
              ? Border.all(color: referenceColor!, width: 1.0)
              : Border.all(
                  color: (isActive || isHighlighted)
                      ? cs.primary
                      : cs.onSurface.withValues(alpha: 0.2),
                  width: 1.0,
                ),
          borderRadius: BorderRadius.zero,
        ),
        padding: const EdgeInsets.all(1),
        child: child,
      ),
    );
  }
}
