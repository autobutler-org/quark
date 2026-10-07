import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The table picker's grid of [extent] by [extent] squares: the squares
/// from the top-left corner to [rows], [columns] are lit, a pointer moving
/// over the grid reports the size under it through [onHover], and a tap
/// picks the size it lands on through [onPicked].
///
/// To a screen reader the grid is one button reading the lit size; the
/// picker's steppers set it square by square.
///
/// Key prefixes: `slide_table_grid` on the grid, `slide_table_grid_<row>_<column>`
/// (from 1) on each square.
class SlideTableSizeGrid extends StatelessWidget {
  /// A grid lit up to [rows] by [columns].
  const SlideTableSizeGrid({
    required this.rows,
    required this.columns,
    required this.onHover,
    required this.onPicked,
    this.extent = 8,
    super.key,
  });

  /// The rows lit.
  final int rows;

  /// The columns lit.
  final int columns;

  /// Called with the size under the pointer as it moves.
  final void Function(int rows, int columns) onHover;

  /// Called with the size tapped.
  final void Function(int rows, int columns) onPicked;

  /// How many squares the grid has across and down.
  final int extent;

  /// The side of a square, in logical pixels.
  static const double square = 22;

  /// The space between squares, in logical pixels.
  static const double gap = 3;

  /// The size at [position] inside the grid, each kept between 1 and
  /// [extent].
  ({int rows, int columns}) sizeAt(Offset position) {
    int at(double v) => (v ~/ (square + gap) + 1).clamp(1, extent);
    return (rows: at(position.dy), columns: at(position.dx));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return Semantics(
      button: true,
      label: 'Table size',
      value: '$rows by $columns',
      onTap: () => onPicked(rows, columns),
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (event) {
          final size = sizeAt(event.localPosition);
          if (size.rows != rows || size.columns != columns) {
            onHover(size.rows, size.columns);
          }
        },
        child: GestureDetector(
          key: const ValueKey('slide_table_grid'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final size = sizeAt(details.localPosition);
            onPicked(size.rows, size.columns);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: gap,
            children: [
              for (var r = 1; r <= extent; r++)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  spacing: gap,
                  children: [
                    for (var c = 1; c <= extent; c++)
                      DecoratedBox(
                        key: ValueKey('slide_table_grid_${r}_$c'),
                        decoration: BoxDecoration(
                          color: r <= rows && c <= columns
                              ? tokens.primary.withValues(alpha: 0.35)
                              : tokens.card,
                          border: Border.all(
                            color: r <= rows && c <= columns
                                ? tokens.primary
                                : tokens.border,
                          ),
                          borderRadius: BorderRadius.circular(tokens.radiusSm),
                        ),
                        child: const SizedBox.square(dimension: square),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
