import '../evaluator/evaluator.dart';
import '../evaluator/values.dart';
import '../lexer/lexer.dart';
import '../parser/parser.dart';
import 'dependency_graph.dart';
import 'scc.dart';
import 'topological_sort.dart';

export 'dependency_graph.dart';
export 'scc.dart';
export 'topological_sort.dart';

const _circularError = ErrorValue('#REF!', 'Circular reference');

/// Orchestrates full-sheet parsing, dependency-graph construction, cycle
/// detection (Tarjan SCC), and topological evaluation (Kahn's algorithm).
///
/// Formula cells are any whose raw string starts with `=`. All other cells are
/// treated as literals.
class DataSheetInterpreter {
  /// Evaluates every formula cell in a sheet and returns a map from
  /// `(row, col)` to its computed [FormulaValue].
  ///
  /// Only formula cells appear in the returned map; literal cells are resolved
  /// on demand through the [rawCellValue] accessor when another formula
  /// references them.
  ///
  /// [rows] and [cols] are the dimensions of the sheet (0-based iteration).
  /// [rawCellValue] returns the raw string for a given `(row, col)`.
  Map<(int, int), FormulaValue> interpretSheet(
    int rows,
    int cols,
    String Function(int, int) rawCellValue,
  ) {
    // ── Stage 1: parse all formula cells ────────────────────────────────────
    final parsedFormulas = <(int, int), ParsedFormula>{};
    final parseErrors = <(int, int), FormulaValue>{};

    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final raw = rawCellValue(r, c);
        if (!raw.startsWith('=')) continue;
        try {
          parsedFormulas[(r, c)] = parseTokens(lex(raw));
        } on LexError catch (e) {
          parseErrors[(r, c)] = valueError(
            "Couldn't read the formula: ${e.message}",
          );
        } catch (_) {
          parseErrors[(r, c)] = valueError("Couldn't read the formula");
        }
      }
    }

    // ── Stage 2: build dependency graph ─────────────────────────────────────
    final graph = DependencyGraph();

    for (final entry in parsedFormulas.entries) {
      final cell = entry.key;
      final formula = entry.value;
      graph.ensureNode(cell);

      for (final ref in formula.cellRefs) {
        final dep = _parseCellRef(ref);
        if (dep != null) {
          graph.addEdge(cell, dep);
        }
      }

      for (final rangeRef in formula.rangeRefs) {
        final colonIdx = rangeRef.indexOf(':');
        if (colonIdx < 0) continue;
        final start = _parseCellRef(rangeRef.substring(0, colonIdx));
        final end = _parseCellRef(rangeRef.substring(colonIdx + 1));
        if (start == null || end == null) continue;
        final rowMin = start.$1 < end.$1 ? start.$1 : end.$1;
        final rowMax = start.$1 > end.$1 ? start.$1 : end.$1;
        final colMin = start.$2 < end.$2 ? start.$2 : end.$2;
        final colMax = start.$2 > end.$2 ? start.$2 : end.$2;
        for (var r = rowMin; r <= rowMax; r++) {
          for (var c = colMin; c <= colMax; c++) {
            graph.addEdge(cell, (r, c));
          }
        }
      }
    }

    // ── Stage 3: detect cycles with Tarjan's SCC ────────────────────────────
    final cycleMembers = findCycleMembers(graph);

    // ── Stage 4: topological evaluation with Kahn's algorithm ───────────────
    final results = <(int, int), FormulaValue>{};

    // Pre-assign error values to all cycle members.
    for (final cell in cycleMembers) {
      results[cell] = _circularError;
    }

    final sorted = kahnSort(
      parsedFormulas.keys.toSet(),
      graph.dependsOn,
      excludedNodes: cycleMembers,
    );

    for (final cell in sorted.order) {
      final formula = parsedFormulas[cell];
      if (formula == null) continue;

      results[cell] = evaluate(
        formula,
        (r, c) {
          final key = (r, c);
          if (results.containsKey(key)) return results[key]!;
          return _readLiteral(rawCellValue(r, c));
        },
        originRow: cell.$1,
        originCol: cell.$2,
      );
    }

    // Merge parse errors last (they win over any prior partial results).
    results.addAll(parseErrors);

    return results;
  }

  /// Converts a raw literal string to a [FormulaValue].
  FormulaValue _readLiteral(String raw) {
    if (raw.isEmpty) return blankValue;
    final number = double.tryParse(raw);
    if (number != null) return NumberValue(number);
    final lower = raw.toLowerCase();
    if (lower == 'true') return const BoolValue(true);
    if (lower == 'false') return const BoolValue(false);
    return StringValue(raw);
  }

  /// Parses a cell reference string such as "A1" into zero-based `(row, col)`.
  (int, int)? _parseCellRef(String ref) {
    var splitIndex = 0;
    while (splitIndex < ref.length && _isAlpha(ref.codeUnitAt(splitIndex))) {
      splitIndex++;
    }
    if (splitIndex == 0 || splitIndex == ref.length) return null;

    final columnText = ref.substring(0, splitIndex);
    final rowText = ref.substring(splitIndex);
    final row = int.tryParse(rowText);
    if (row == null || row <= 0) return null;

    var column = 0;
    for (final rune in columnText.runes) {
      final upper = String.fromCharCode(rune).toUpperCase().codeUnitAt(0);
      if (!_isAlpha(upper)) return null;
      column = column * 26 + (upper - 64);
    }

    return (row - 1, column - 1);
  }

  bool _isAlpha(int codeUnit) =>
      (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);
}
