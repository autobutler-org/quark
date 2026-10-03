import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show TextRange;
import 'package:quark_formula/evaluation/evaluation.dart'
    show LexError, Token, TokenKind, lex;

import '../cell_range.dart';

/// Colors for the references in a formula being edited, in the order they are handed out. A reference's text in
/// the editor and the outline of the cells it names share one color.
const kFormulaReferencePalette = [
  Color(0xFFD00000), // red
  Color(0xFF4361EE), // blue
  Color(0xFF2B9348), // green
  Color(0xFFFF7B00), // orange
  Color(0xFF7B2CBF), // violet
  Color(0xFF0A9396), // teal
  Color(0xFFB5179E), // magenta
  Color(0xFFCA6702), // amber
  Color(0xFF1D3557), // navy
  Color(0xFF55A630), // leaf
];

/// One cell or range reference in a formula: where it sits in the text ([source]), its normalized [label]
/// (`B2:D9`), the [cells] it names, and its [color].
class FormulaReference {
  /// Where the reference sits in the formula, `$` signs and case as typed.
  final TextRange source;

  /// The reference upper-cased without `$`: `B2` or `B2:D9`.
  final String label;

  /// The cells it names.
  final CellRange cells;

  /// Its color from [kFormulaReferencePalette]; references with the same [label] share one.
  final Color color;

  const FormulaReference({
    required this.source,
    required this.label,
    required this.cells,
    required this.color,
  });
}

/// The cell and range references in [formula], left to right, each colored.
///
/// Colors go out in order of first appearance, so a reference keeps its color while the rest of the formula is
/// typed, and a repeated reference reuses its color. A formula that does not lex to the end (an unfinished string,
/// a stray character) still yields the references before the problem. Text that is not a formula has none.
List<FormulaReference> formulaReferences(String formula) {
  if (!formula.startsWith('=')) return const [];
  final tokens = <Token>[];
  try {
    for (final token in lex(formula)) {
      tokens.add(token);
    }
  } on LexError {
    // Keep the tokens before the error.
  }

  final colors = <String, Color>{};
  final references = <FormulaReference>[];
  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i].kind != TokenKind.cellRef) continue;
    final first = tokens[i];
    var label = first.value;
    var last = first;
    if (i + 2 < tokens.length &&
        tokens[i + 1].kind == TokenKind.colon &&
        tokens[i + 2].kind == TokenKind.cellRef) {
      last = tokens[i + 2];
      label = '$label:${last.value}';
      i += 2;
    }
    final cells = CellRange.tryParse(label);
    if (cells == null) continue;
    references.add(
      FormulaReference(
        // Token offsets skip the leading '='.
        source: TextRange(
          start: first.offset + 1,
          end: _wordEnd(formula, last.offset + 1),
        ),
        label: label,
        cells: cells,
        color: colors.putIfAbsent(
          label,
          () => kFormulaReferencePalette[
              colors.length % kFormulaReferencePalette.length],
        ),
      ),
    );
  }
  return references;
}

/// Each cell the references in [formula] cover, inside a sheet of [rowCount] by [colCount], mapped to its
/// reference's color. Where references overlap, the later one wins.
Map<(int, int), Color> formulaReferenceCellColors(
  String formula, {
  required int rowCount,
  required int colCount,
}) {
  final colors = <(int, int), Color>{};
  for (final reference in formulaReferences(formula)) {
    final cells = reference.cells;
    for (var r = cells.top; r <= cells.bottom && r < rowCount; r++) {
      for (var c = cells.left; c <= cells.right && c < colCount; c++) {
        colors[(r, c)] = reference.color;
      }
    }
  }
  return colors;
}

/// The end of the reference word starting at [from] in [source]: letters, digits and `$`.
int _wordEnd(String source, int from) {
  var i = from;
  while (i < source.length) {
    final c = source.codeUnitAt(i);
    final isWord = c == 0x24 ||
        (c >= 65 && c <= 90) ||
        (c >= 97 && c <= 122) ||
        (c >= 48 && c <= 57);
    if (!isWord) break;
    i++;
  }
  return i;
}
