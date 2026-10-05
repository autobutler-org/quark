import 'values.dart';

/// A built-in spreadsheet function's implementation, called with its arguments already resolved to values or
/// ranges.
typedef BuiltinFn = FormulaValue Function(List<ResolvedArgument> arguments);

/// One argument to a built-in, resolved before the call: a single value or the cells of a range.
sealed class ResolvedArgument {
  const ResolvedArgument();

  Iterable<FormulaValue> get values;
}

/// An argument that resolved to one value.
final class ScalarArgument extends ResolvedArgument {
  final FormulaValue value;

  const ScalarArgument(this.value);

  @override
  Iterable<FormulaValue> get values => [value];
}

/// An argument that was a range, resolved to its cells' values row by row.
final class RangeArgument extends ResolvedArgument {
  final List<FormulaValue> cells;

  const RangeArgument(this.cells);

  @override
  Iterable<FormulaValue> get values => cells;
}

/// A built-in function as an editor shows it: its [name], how to call it ([signature], with optional arguments in
/// brackets) and a one-line [description], beside the [function] the evaluator runs.
///
/// ```dart
/// const BuiltinFunction('SUM', 'SUM(value1, [value2, ...])', 'Adds numbers and ranges.', _sum);
/// ```
final class BuiltinFunction {
  /// The upper-case name a formula calls it by, e.g. `SUM`.
  final String name;

  /// How to call it, e.g. `ROUND(value, [places])`.
  final String signature;

  /// What it does, in one sentence.
  final String description;

  /// The implementation.
  final BuiltinFn function;

  const BuiltinFunction(
    this.name,
    this.signature,
    this.description,
    this.function,
  );

  @override
  String toString() => 'BuiltinFunction($signature)';
}
