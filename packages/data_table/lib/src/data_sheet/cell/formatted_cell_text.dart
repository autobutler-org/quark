import 'package:flutter/material.dart';

import '../../models/cell_format.dart';

/// A cell's shown text in its [CellFormat]: bold, italic, text color and
/// alignment. [text] is already in the cell's number format. A formula error
/// shows as a `FormulaErrorChip` instead.
class FormattedCellText extends StatelessWidget {
  /// The text to show, already number-formatted.
  final String text;

  /// The cell's format.
  final CellFormat format;

  const FormattedCellText({
    super.key,
    required this.text,
    required this.format,
  });

  @override
  Widget build(BuildContext context) {
    final color = format.textColor == null ? null : Color(format.textColor!);
    return Text(
      text,
      textAlign: switch (format.align) {
        CellAlign.center => TextAlign.center,
        CellAlign.right => TextAlign.right,
        CellAlign.left || null => TextAlign.left,
      },
      style: TextStyle(
        color: color,
        fontWeight: format.bold ? FontWeight.bold : null,
        fontStyle: format.italic ? FontStyle.italic : null,
      ),
    );
  }
}
