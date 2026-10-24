# quark_formula

## Purpose

quark_formula is a lightweight, standalone formula evaluation engine extracted from the data_table package. It provides parsing and evaluation primitives and a small built-in function registry. It is framework-agnostic and usable from Dart or Flutter code.

## Installation (local path)

To use the package from the monorepo during development, add a path dependency in your pubspec.yaml:

dependencies:
quark_formula:
path: packages/quark_formula

Then run `dart pub get` or `flutter pub get` in your consuming package.

## Public API (quick reference)

Public surface (not exhaustive):

- package:quark_formula/evaluation/evaluation.dart
  - The package's one entrypoint. Re-exports the lexer, parser, evaluator and interpreter, and `parseCellRef`, which
    reads an A1 reference such as `B2` as zero-based `(row, col)`.

Key types and entrypoints (from evaluation/evaluator):

- typedef CellAccessor = FormulaValue Function(int row, int col)
  - A callback that resolves a (row,col) to a FormulaValue for the evaluator.

- FormulaValue and subtypes (NumberValue, StringValue, BoolValue, ErrorValue)
  - Result types returned by evaluation.

- FormulaValue evaluate(ParsedFormula formula, CellAccessor cellAccessor, {int originRow=0, int originCol=0, Map<String,BuiltinFn>? builtins})
  - High-level entrypoint to evaluate a parsed formula.

- class FormulaEvaluator
  - Stateful evaluator that can be constructed with a CellAccessor and optional builtin overrides.

## Usage example (minimal)

This example shows a minimal CellAccessor that reads values from a DataSheetController (from the data_table package) and evaluates a parsed formula.

```dart
import 'package:quark_formula/evaluation/evaluation.dart' as eval;
import 'package:quark_formula/evaluation/evaluator/evaluator.dart' show CellAccessor, evaluate, NumberValue, StringValue, BoolValue;
import 'package:data_table/data_table.dart' show DataSheetController, DataCell;

// Given an existing DataSheetController `controller`:
final DataSheetController controller = /* obtain controller */ throw UnimplementedError();

// Convert a DataCell's value into a FormulaValue.
FormulaValue _fromCell(DataCell cell) {
  final v = cell.value;
  if (v == null || v.toString().isEmpty) return StringValue('');
  final n = double.tryParse(v.toString());
  if (n != null) return NumberValue(n);
  final low = v.toString().toLowerCase();
  if (low == 'true' || low == 'false') return BoolValue(low == 'true');
  return StringValue(v.toString());
}

// Provide CellAccessor wiring to DataSheetController.
final CellAccessor accessor = (int row, int col) {
  final cell = controller.cellAt(row, col);
  return _fromCell(cell);
};

// Parse a formula (using the evaluation parser) and evaluate it.
final parsed = /* use evaluation parser: package:quark_formula/evaluation/parser/parser.dart */ throw UnimplementedError();
final result = evaluate(parsed, accessor);

// Inspect result: NumberValue, StringValue, BoolValue, or ErrorValue
```

## Notes

- For licensing and attribution, see the repository LICENSE at the project root.

## Contributing and tests

Run package tests from the repo root:

dart test packages/quark_formula

## Feedback

Open issues or PRs in the monorepo. Keep the README focused — more examples live alongside the data_table package which uses quark_formula.
