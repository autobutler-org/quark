import 'package:flutter/material.dart';

import '../../models/cell_format.dart';

/// A cell's shown text in its [CellFormat]: bold, italic, text color and
/// alignment. [text] is already in the cell's number format.
///
/// An error result (`#REF!`, `#DIV/0!`) draws in the theme's error color over
/// any text color, so it never hides.
class FormattedCellText extends StatelessWidget {
  /// The text to show, already number-formatted.
  final String text;

  /// The cell's format.
  final CellFormat format;

  /// Whether the cell's formula evaluated to an error.
  final bool isError;

  const FormattedCellText({
    super.key,
    required this.text,
    required this.format,
    this.isError = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : format.textColor == null
            ? null
            : Color(format.textColor!);
    return Text(
      text,
      textAlign: switch (format.align) {
        CellAlign.center => TextAlign.center,
        CellAlign.right => TextAlign.right,
        CellAlign.left || null => TextAlign.left,
      },
      style: TextStyle(
        color: color,
        fontWeight: format.bold
            ? FontWeight.bold
            : isError
                ? FontWeight.w500
                : null,
        fontStyle: format.italic ? FontStyle.italic : null,
      ),
    );
  }
}
