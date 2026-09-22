// Formula error definitions

/// An error from the prototype formula engine.
class FormulaError implements Exception {
  final String message;
  FormulaError(this.message);
  @override
  String toString() => 'FormulaError: $message';
}
