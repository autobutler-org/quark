import 'package:flutter/material.dart';

import '../cell/heading/heading_cells.dart' show kFrozenDividerThickness;

/// The line between frozen and scrolling panes of a `DataSheet`.
///
/// [Axis.horizontal] draws the line under the frozen rows, [Axis.vertical]
/// the line beside the frozen columns. It is [kFrozenDividerThickness] thick
/// in the theme's outline color (derived from `QuarkTokens` under
/// `QuarkTheme`) and ignores the pointer, so it never takes a tap from the
/// cells it overlaps.
///
/// Keys: the grid gives it `frozen_rows_divider` or `frozen_columns_divider`.
class FrozenPaneDivider extends StatelessWidget {
  /// The direction the line runs.
  final Axis axis;

  /// Creates a divider running along [axis].
  const FrozenPaneDivider({super.key, required this.axis});

  @override
  Widget build(BuildContext context) {
    final horizontal = axis == Axis.horizontal;
    return IgnorePointer(
      child: Container(
        width: horizontal ? null : kFrozenDividerThickness,
        height: horizontal ? kFrozenDividerThickness : null,
        color: Theme.of(context).colorScheme.outline,
      ),
    );
  }
}
