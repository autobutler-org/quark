import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One cell of a chart's data sheet: a series name, a category, or a
/// value. A value that is not a number shows [error] under it and reads
/// to a screen reader with it; [label] names the cell ("Q2, Revenue").
///
/// It starts at [initial] and reports each keystroke through [onChanged];
/// the sheet rebuilds the grid with fresh cells when rows or columns move,
/// so it never needs to take a new value in place.
///
/// Key prefixes: the [cellKey] it is given, `slide_chart_cell_<row>_<column>`.
class SlideChartDataCell extends StatelessWidget {
  /// A cell keyed [cellKey], starting at [initial].
  const SlideChartDataCell({
    required this.cellKey,
    required this.label,
    required this.initial,
    required this.onChanged,
    this.numeric = false,
    this.header = false,
    this.error,
    super.key,
  });

  /// The field's `ValueKey` name.
  final String cellKey;

  /// What the cell is, for a screen reader and the hint.
  final String label;

  /// The text it starts with.
  final String initial;

  /// Called with the text on every change.
  final ValueChanged<String> onChanged;

  /// Whether it holds a value, which brings up a number keyboard.
  final bool numeric;

  /// Whether it names a series or a category, drawn bold.
  final bool header;

  /// Why its value is refused; null when it is fine.
  final String? error;

  /// How wide a cell is.
  static const double width = 128;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.all(tokens.spacingXs),
        // On screen the first row and column say what a cell is; a screen
        // reader hears it as "Q2, Revenue".
        child: Semantics(
          label: label,
          child: TextFormField(
            key: ValueKey(cellKey),
            initialValue: initial,
            onChanged: onChanged,
            keyboardType: numeric
                ? const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  )
                : TextInputType.text,
            textAlign: numeric ? TextAlign.end : TextAlign.start,
            textInputAction: TextInputAction.next,
            autocorrect: false,
            style: header ? const TextStyle(fontWeight: FontWeight.w600) : null,
            decoration: InputDecoration(
              isDense: true,
              hintText: numeric ? '0' : null,
              errorText: error,
              errorMaxLines: 2,
            ),
          ),
        ),
      ),
    );
  }
}
