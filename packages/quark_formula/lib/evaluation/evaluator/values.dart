/// A value a formula can produce: a number, string, boolean, or error.
sealed class FormulaValue {
  const FormulaValue();

  bool get isError => this is ErrorValue;
}

final class NumberValue extends FormulaValue {
  final double value;

  const NumberValue(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is NumberValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'NumberValue($value)';
}

final class StringValue extends FormulaValue {
  final String value;

  const StringValue(this.value);

  bool get isBlank => value.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is StringValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'StringValue($value)';
}

final class BoolValue extends FormulaValue {
  final bool value;

  const BoolValue(this.value);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BoolValue && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'BoolValue($value)';
}

final class ErrorValue extends FormulaValue {
  final String code;
  final String message;

  const ErrorValue(this.code, this.message);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ErrorValue && other.code == code && other.message == message;

  @override
  int get hashCode => Object.hash(code, message);

  @override
  String toString() => 'ErrorValue($code, $message)';
}

const StringValue blankValue = StringValue('');

ErrorValue div0Error([String message = 'Division by zero']) =>
    ErrorValue('#DIV/0!', message);

ErrorValue nameError([String message = 'Unknown function']) =>
    ErrorValue('#NAME?', message);

ErrorValue refError([String message = 'Invalid reference']) =>
    ErrorValue('#REF!', message);

ErrorValue valueError([String message = 'Type mismatch']) =>
    ErrorValue('#VALUE!', message);
