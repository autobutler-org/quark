import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The properties panel's table section (#1160): how many [rows] and
/// [columns] the selected table has, and switches for its header row and
/// banded rows. A null handler — a view-only presentation — leaves its
/// switch showing but off to input.
///
/// Position and size are the panel's ordinary fields above it.
///
/// Key prefixes: `slide_prop_table_size` on the size,
/// `slide_prop_table_header_row` and `slide_prop_table_banded_rows` on the
/// switches.
class SlideTablePropertiesSection extends StatelessWidget {
  /// The section for a [rows] by [columns] table.
  const SlideTablePropertiesSection({
    required this.rows,
    required this.columns,
    required this.headerRow,
    required this.bandedRows,
    this.onHeaderRowChanged,
    this.onBandedRowsChanged,
    super.key,
  });

  /// How many rows the table has.
  final int rows;

  /// How many columns the table has.
  final int columns;

  /// Whether the first row is a header row.
  final bool headerRow;

  /// Whether every other body row is shaded.
  final bool bandedRows;

  /// Turns the header row on or off; null takes no input.
  final ValueChanged<bool>? onHeaderRowChanged;

  /// Turns the banded rows on or off; null takes no input.
  final ValueChanged<bool>? onBandedRowsChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    String count(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    return QuarkSection(
      title: 'Table',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${count(rows, 'row')} × ${count(columns, 'column')}',
            key: const ValueKey('slide_prop_table_size'),
            semanticsLabel:
                '${count(rows, 'row')} by ${count(columns, 'column')}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: tokens.foreground),
          ),
          for (final (key, label, value, onChanged) in [
            (
              'slide_prop_table_header_row',
              'Header row',
              headerRow,
              onHeaderRowChanged,
            ),
            (
              'slide_prop_table_banded_rows',
              'Banded rows',
              bandedRows,
              onBandedRowsChanged,
            ),
          ])
            SwitchListTile(
              key: ValueKey(key),
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              value: value,
              onChanged: onChanged,
            ),
        ],
      ),
    );
  }
}
