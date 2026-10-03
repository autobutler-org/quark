import 'package:flutter/material.dart';

import 'formula_references.dart';

/// A [TextEditingController] that draws each cell or range reference in a formula in its
/// [kFormulaReferencePalette] color, the color the grid outlines those cells in.
///
/// The colors come from the text alone ([formulaReferences]), so the cell editor and the formula bar color the
/// same formula the same way. Text that is not a formula, and text mid-composition in an input method, draw
/// plainly.
class FormulaTextEditingController extends TextEditingController {
  /// A controller starting with [text].
  FormulaTextEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final references = formulaReferences(text);
    if (references.isEmpty || withComposing && value.composing.isValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final reference in references) {
      final source = reference.source;
      if (source.start > cursor) {
        spans.add(TextSpan(text: text.substring(cursor, source.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(source.start, source.end),
          style: TextStyle(
            color: reference.color,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      cursor = source.end;
    }
    if (cursor < text.length) spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(style: style, children: spans);
  }
}
