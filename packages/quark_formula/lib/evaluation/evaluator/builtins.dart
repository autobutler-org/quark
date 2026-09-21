import 'dart:math' as math;

import 'values.dart';

/// A built-in spreadsheet function, called with its arguments already resolved to values or ranges. This file
/// holds the table of built-ins by name.
typedef BuiltinFn = FormulaValue Function(List<ResolvedArgument> arguments);
typedef _NumberResult = ({double? value, ErrorValue? error});
typedef _StringResult = ({String? value, ErrorValue? error});
typedef _BoolResult = ({bool? value, ErrorValue? error});
typedef _NumbersResult = ({List<double>? values, ErrorValue? error});

sealed class ResolvedArgument {
  const ResolvedArgument();

  Iterable<FormulaValue> get values;
}

final class ScalarArgument extends ResolvedArgument {
  final FormulaValue value;

  const ScalarArgument(this.value);

  @override
  Iterable<FormulaValue> get values => [value];
}

final class RangeArgument extends ResolvedArgument {
  final List<FormulaValue> cells;

  const RangeArgument(this.cells);

  @override
  Iterable<FormulaValue> get values => cells;
}

final Map<String, BuiltinFn> builtinFunctions = <String, BuiltinFn>{
  'SUM': _sum,
  'AVERAGE': _average,
  'MIN': _min,
  'MAX': _max,
  'ABS': _abs,
  'ROUND': _round,
  'FLOOR': _floor,
  'CEILING': _ceiling,
  'MOD': _mod,
  'POWER': _power,
  'SQRT': _sqrt,
  'CONCAT': _concat,
  'LEN': _len,
  'UPPER': _upper,
  'LOWER': _lower,
  'TRIM': _trim,
  'LEFT': _left,
  'RIGHT': _right,
  'MID': _mid,
  'FIND': _find,
  'SUBSTITUTE': _substitute,
  'IF': _ifFn,
  'AND': _and,
  'OR': _or,
  'NOT': _not,
  'IFERROR': _ifError,
  'ISBLANK': _isBlank,
  'ISNUMBER': _isNumber,
  'ISTEXT': _isText,
  'COUNT': _count,
  'COUNTA': _countA,
  'COUNTIF': _countIf,
};

FormulaValue _sum(List<ResolvedArgument> arguments) {
  final result = _collectNumbers(arguments, allowEmpty: true);
  if (result.error != null) {
    return result.error!;
  }
  return NumberValue(result.values!.fold(0, (sum, value) => sum + value));
}

FormulaValue _average(List<ResolvedArgument> arguments) {
  final result = _collectNumbers(arguments, allowEmpty: false);
  if (result.error != null) {
    return result.error!;
  }
  final values = result.values!;
  return NumberValue(values.reduce((a, b) => a + b) / values.length);
}

FormulaValue _min(List<ResolvedArgument> arguments) {
  final result = _collectNumbers(arguments, allowEmpty: false);
  if (result.error != null) {
    return result.error!;
  }
  return NumberValue(result.values!.reduce(math.min));
}

FormulaValue _max(List<ResolvedArgument> arguments) {
  final result = _collectNumbers(arguments, allowEmpty: false);
  if (result.error != null) {
    return result.error!;
  }
  return NumberValue(result.values!.reduce(math.max));
}

FormulaValue _abs(List<ResolvedArgument> arguments) {
  final result = _expectNumberArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return NumberValue(result.value!.abs());
}

FormulaValue _round(List<ResolvedArgument> arguments) {
  final numberResult = _expectNumberArg(arguments, 0, minCount: 1, maxCount: 2);
  if (numberResult.error != null) {
    return numberResult.error!;
  }
  final digitsResult = arguments.length == 1
      ? (value: 0.0, error: null)
      : _expectNumberArg(arguments, 1, minCount: 1, maxCount: 2);
  if (digitsResult.error != null) {
    return digitsResult.error!;
  }

  final number = numberResult.value!;
  final digits = digitsResult.value!;
  final scale = math.pow(10, digits.toInt()).toDouble();
  return NumberValue((number * scale).round() / scale);
}

FormulaValue _floor(List<ResolvedArgument> arguments) {
  final result = _expectNumberArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return NumberValue(result.value!.floorToDouble());
}

FormulaValue _ceiling(List<ResolvedArgument> arguments) {
  final result = _expectNumberArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return NumberValue(result.value!.ceilToDouble());
}

FormulaValue _mod(List<ResolvedArgument> arguments) {
  final leftResult = _expectNumberArg(arguments, 0, exactCount: 2);
  if (leftResult.error != null) {
    return leftResult.error!;
  }
  final rightResult = _expectNumberArg(arguments, 1, exactCount: 2);
  if (rightResult.error != null) {
    return rightResult.error!;
  }
  final left = leftResult.value!;
  final right = rightResult.value!;
  if (right == 0) {
    return div0Error();
  }
  return NumberValue(left % right);
}

FormulaValue _power(List<ResolvedArgument> arguments) {
  final leftResult = _expectNumberArg(arguments, 0, exactCount: 2);
  if (leftResult.error != null) {
    return leftResult.error!;
  }
  final rightResult = _expectNumberArg(arguments, 1, exactCount: 2);
  if (rightResult.error != null) {
    return rightResult.error!;
  }
  return NumberValue(
      math.pow(leftResult.value!, rightResult.value!).toDouble());
}

FormulaValue _sqrt(List<ResolvedArgument> arguments) {
  final result = _expectNumberArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  final number = result.value!;
  if (number < 0) {
    return valueError('SQRT expects a non-negative number');
  }
  return NumberValue(math.sqrt(number));
}

FormulaValue _concat(List<ResolvedArgument> arguments) {
  final values = <String>[];
  for (final argument in arguments) {
    for (final value in argument.values) {
      if (value is ErrorValue) {
        return value;
      }
      values.add(_stringify(value));
    }
  }
  return StringValue(values.join());
}

FormulaValue _len(List<ResolvedArgument> arguments) {
  final result = _expectStringArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return NumberValue(result.value!.length.toDouble());
}

FormulaValue _upper(List<ResolvedArgument> arguments) {
  final result = _expectStringArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return StringValue(result.value!.toUpperCase());
}

FormulaValue _lower(List<ResolvedArgument> arguments) {
  final result = _expectStringArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return StringValue(result.value!.toLowerCase());
}

FormulaValue _trim(List<ResolvedArgument> arguments) {
  final result = _expectStringArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return StringValue(result.value!.trim().replaceAll(RegExp(r'\s+'), ' '));
}

FormulaValue _left(List<ResolvedArgument> arguments) {
  final textResult = _expectStringArg(arguments, 0, minCount: 1, maxCount: 2);
  if (textResult.error != null) {
    return textResult.error!;
  }
  final countResult = arguments.length == 1
      ? (value: 1.0, error: null)
      : _expectNumberArg(arguments, 1, minCount: 1, maxCount: 2);
  if (countResult.error != null) {
    return countResult.error!;
  }
  final text = textResult.value!;
  final end = countResult.value!.toInt().clamp(0, text.length);
  return StringValue(text.substring(0, end));
}

FormulaValue _right(List<ResolvedArgument> arguments) {
  final textResult = _expectStringArg(arguments, 0, minCount: 1, maxCount: 2);
  if (textResult.error != null) {
    return textResult.error!;
  }
  final countResult = arguments.length == 1
      ? (value: 1.0, error: null)
      : _expectNumberArg(arguments, 1, minCount: 1, maxCount: 2);
  if (countResult.error != null) {
    return countResult.error!;
  }
  final text = textResult.value!;
  final length = countResult.value!.toInt().clamp(0, text.length);
  return StringValue(text.substring(text.length - length));
}

FormulaValue _mid(List<ResolvedArgument> arguments) {
  final textResult = _expectStringArg(arguments, 0, exactCount: 3);
  if (textResult.error != null) {
    return textResult.error!;
  }
  final startResult = _expectNumberArg(arguments, 1, exactCount: 3);
  if (startResult.error != null) {
    return startResult.error!;
  }
  final countResult = _expectNumberArg(arguments, 2, exactCount: 3);
  if (countResult.error != null) {
    return countResult.error!;
  }
  final text = textResult.value!;
  final startIndex = math.max(0, startResult.value!.toInt() - 1);
  final endIndex = math
      .min(
        text.length,
        startIndex + math.max(0, countResult.value!.toInt()),
      )
      .toInt();
  if (startIndex >= text.length) {
    return const StringValue('');
  }
  return StringValue(text.substring(startIndex, endIndex));
}

FormulaValue _find(List<ResolvedArgument> arguments) {
  final needleResult = _expectStringArg(arguments, 0, minCount: 2, maxCount: 3);
  if (needleResult.error != null) {
    return needleResult.error!;
  }
  final haystackResult =
      _expectStringArg(arguments, 1, minCount: 2, maxCount: 3);
  if (haystackResult.error != null) {
    return haystackResult.error!;
  }
  final startResult = arguments.length == 2
      ? (value: 1.0, error: null)
      : _expectNumberArg(arguments, 2, minCount: 2, maxCount: 3);
  if (startResult.error != null) {
    return startResult.error!;
  }
  final index = haystackResult.value!.indexOf(
    needleResult.value!,
    math.max(0, startResult.value!.toInt() - 1),
  );
  if (index == -1) {
    return valueError('FIND could not locate the requested text');
  }
  return NumberValue((index + 1).toDouble());
}

FormulaValue _substitute(List<ResolvedArgument> arguments) {
  final textResult = _expectStringArg(arguments, 0, minCount: 3, maxCount: 4);
  if (textResult.error != null) {
    return textResult.error!;
  }
  final oldTextResult =
      _expectStringArg(arguments, 1, minCount: 3, maxCount: 4);
  if (oldTextResult.error != null) {
    return oldTextResult.error!;
  }
  final newTextResult =
      _expectStringArg(arguments, 2, minCount: 3, maxCount: 4);
  if (newTextResult.error != null) {
    return newTextResult.error!;
  }
  final text = textResult.value!;
  final oldText = oldTextResult.value!;
  final newText = newTextResult.value!;
  if (arguments.length == 3) {
    return StringValue(text.replaceAll(oldText, newText));
  }
  final instanceResult =
      _expectNumberArg(arguments, 3, minCount: 3, maxCount: 4);
  if (instanceResult.error != null) {
    return instanceResult.error!;
  }
  final target = instanceResult.value!.toInt();
  if (target <= 0) {
    return valueError('SUBSTITUTE instance must be positive');
  }

  var seen = 0;
  var start = 0;
  final buffer = StringBuffer();
  while (true) {
    final foundAt = text.indexOf(oldText, start);
    if (foundAt == -1) {
      buffer.write(text.substring(start));
      return StringValue(buffer.toString());
    }
    seen++;
    buffer.write(text.substring(start, foundAt));
    buffer.write(seen == target ? newText : oldText);
    start = foundAt + oldText.length;
  }
}

FormulaValue _ifFn(List<ResolvedArgument> arguments) {
  final result = _expectBoolArg(arguments, 0, exactCount: 3);
  if (result.error != null) {
    return result.error!;
  }
  return _singleValue(arguments[result.value! ? 1 : 2]);
}

FormulaValue _and(List<ResolvedArgument> arguments) {
  if (arguments.isEmpty) {
    return valueError('AND expects at least one argument');
  }
  for (final argument in arguments) {
    for (final value in argument.values) {
      if (value is ErrorValue) {
        return value;
      }
      if (value is! BoolValue) {
        return valueError('AND expects boolean arguments');
      }
      if (!value.value) {
        return const BoolValue(false);
      }
    }
  }
  return const BoolValue(true);
}

FormulaValue _or(List<ResolvedArgument> arguments) {
  if (arguments.isEmpty) {
    return valueError('OR expects at least one argument');
  }
  for (final argument in arguments) {
    for (final value in argument.values) {
      if (value is ErrorValue) {
        return value;
      }
      if (value is! BoolValue) {
        return valueError('OR expects boolean arguments');
      }
      if (value.value) {
        return const BoolValue(true);
      }
    }
  }
  return const BoolValue(false);
}

FormulaValue _not(List<ResolvedArgument> arguments) {
  final result = _expectBoolArg(arguments, 0, exactCount: 1);
  if (result.error != null) {
    return result.error!;
  }
  return BoolValue(!result.value!);
}

FormulaValue _ifError(List<ResolvedArgument> arguments) {
  if (arguments.length != 2) {
    return valueError('IFERROR expects exactly two arguments');
  }
  final primary = _singleValue(arguments[0]);
  if (primary is ErrorValue) {
    return _singleValue(arguments[1]);
  }
  return primary;
}

FormulaValue _isBlank(List<ResolvedArgument> arguments) {
  final value = _expectSingle(arguments, exactCount: 1);
  return switch (value) {
    ErrorValue error => error,
    StringValue text => BoolValue(text.isBlank),
    _ => const BoolValue(false),
  };
}

FormulaValue _isNumber(List<ResolvedArgument> arguments) {
  final value = _expectSingle(arguments, exactCount: 1);
  return switch (value) {
    ErrorValue error => error,
    NumberValue _ => const BoolValue(true),
    _ => const BoolValue(false),
  };
}

FormulaValue _isText(List<ResolvedArgument> arguments) {
  final value = _expectSingle(arguments, exactCount: 1);
  return switch (value) {
    ErrorValue error => error,
    StringValue _ => const BoolValue(true),
    _ => const BoolValue(false),
  };
}

FormulaValue _count(List<ResolvedArgument> arguments) {
  var count = 0;
  for (final argument in arguments) {
    for (final value in argument.values) {
      if (value is ErrorValue) {
        return value;
      }
      if (value is NumberValue) {
        count++;
      }
    }
  }
  return NumberValue(count.toDouble());
}

FormulaValue _countA(List<ResolvedArgument> arguments) {
  var count = 0;
  for (final argument in arguments) {
    for (final value in argument.values) {
      if (value is ErrorValue) {
        count++;
        continue;
      }
      if (value is StringValue && value.isBlank) {
        continue;
      }
      count++;
    }
  }
  return NumberValue(count.toDouble());
}

FormulaValue _countIf(List<ResolvedArgument> arguments) {
  if (arguments.length != 2) {
    return valueError('COUNTIF expects exactly two arguments');
  }
  final criteriaValue = _singleValue(arguments[1]);
  if (criteriaValue is ErrorValue) {
    return criteriaValue;
  }
  final criteria = _parseCountIfCriteria(criteriaValue);

  var count = 0;
  for (final value in arguments[0].values) {
    if (value is ErrorValue) {
      return value;
    }
    if (criteria(value)) {
      count++;
    }
  }
  return NumberValue(count.toDouble());
}

_NumberResult _expectNumberArg(
  List<ResolvedArgument> arguments,
  int index, {
  int? exactCount,
  int? minCount,
  int? maxCount,
}) {
  final checked = _expectSingle(
    arguments,
    index: index,
    exactCount: exactCount,
    minCount: minCount,
    maxCount: maxCount,
  );
  if (checked is ErrorValue) {
    return (value: null, error: checked);
  }
  if (checked is! NumberValue) {
    return (value: null, error: valueError('Expected a number argument'));
  }
  return (value: checked.value, error: null);
}

_StringResult _expectStringArg(
  List<ResolvedArgument> arguments,
  int index, {
  int? exactCount,
  int? minCount,
  int? maxCount,
}) {
  final checked = _expectSingle(
    arguments,
    index: index,
    exactCount: exactCount,
    minCount: minCount,
    maxCount: maxCount,
  );
  if (checked is ErrorValue) {
    return (value: null, error: checked);
  }
  return (value: _stringify(checked), error: null);
}

_BoolResult _expectBoolArg(
  List<ResolvedArgument> arguments,
  int index, {
  int? exactCount,
  int? minCount,
  int? maxCount,
}) {
  final checked = _expectSingle(
    arguments,
    index: index,
    exactCount: exactCount,
    minCount: minCount,
    maxCount: maxCount,
  );
  if (checked is ErrorValue) {
    return (value: null, error: checked);
  }
  if (checked is! BoolValue) {
    return (value: null, error: valueError('Expected a boolean argument'));
  }
  return (value: checked.value, error: null);
}

_NumbersResult _collectNumbers(
  List<ResolvedArgument> arguments, {
  required bool allowEmpty,
}) {
  final result = <double>[];
  for (final argument in arguments) {
    for (final value in argument.values) {
      if (value is ErrorValue) {
        return (values: null, error: value);
      }
      if (value is StringValue && value.isBlank) {
        continue;
      }
      if (value is! NumberValue) {
        return (values: null, error: valueError('Expected numeric arguments'));
      }
      result.add(value.value);
    }
  }

  if (result.isEmpty && !allowEmpty) {
    return (
      values: null,
      error: valueError('Expected at least one numeric argument'),
    );
  }
  return (values: result, error: null);
}

FormulaValue _expectSingle(
  List<ResolvedArgument> arguments, {
  int index = 0,
  int? exactCount,
  int? minCount,
  int? maxCount,
}) {
  if (exactCount != null && arguments.length != exactCount) {
    return valueError('Expected $exactCount argument(s)');
  }
  if (minCount != null && arguments.length < minCount) {
    return valueError('Expected at least $minCount argument(s)');
  }
  if (maxCount != null && arguments.length > maxCount) {
    return valueError('Expected at most $maxCount argument(s)');
  }
  if (index >= arguments.length) {
    return valueError('Missing argument');
  }
  return _singleValue(arguments[index]);
}

FormulaValue _singleValue(ResolvedArgument argument) {
  if (argument is ScalarArgument) {
    return argument.value;
  }
  if (argument is RangeArgument && argument.cells.length == 1) {
    return argument.cells.single;
  }
  return valueError('Expected a scalar argument');
}

String _stringify(FormulaValue value) {
  return switch (value) {
    NumberValue(:final value) => value.toString(),
    StringValue(:final value) => value,
    BoolValue(:final value) => value ? 'TRUE' : 'FALSE',
    ErrorValue(:final code) => code,
  };
}

bool Function(FormulaValue) _parseCountIfCriteria(FormulaValue criteria) {
  if (criteria is NumberValue) {
    return (value) => value is NumberValue && value.value == criteria.value;
  }
  if (criteria is BoolValue) {
    return (value) => value is BoolValue && value.value == criteria.value;
  }
  if (criteria is! StringValue) {
    return (_) => false;
  }

  const operators = ['>=', '<=', '<>', '!=', '==', '>', '<', '='];
  for (final operator in operators) {
    if (!criteria.value.startsWith(operator)) {
      continue;
    }
    final operandText = criteria.value.substring(operator.length).trim();
    final operandNumber = double.tryParse(operandText);
    if (operandNumber != null) {
      return (value) =>
          value is NumberValue &&
          _matchesDouble(value.value, operator, operandNumber);
    }
    final operandUpper = operandText.toUpperCase();
    if (operandUpper == 'TRUE' || operandUpper == 'FALSE') {
      final operandBool = operandUpper == 'TRUE';
      return (value) =>
          value is BoolValue &&
          _matchesBool(value.value, operator, operandBool);
    }
    return (value) =>
        value is StringValue &&
        _matchesString(value.value, operator, operandText);
  }

  return (value) => switch (value) {
        StringValue(:final value) => value == criteria.value,
        _ => false,
      };
}

bool _matchesDouble(double value, String operator, double operand) {
  return switch (operator) {
    '>' => value > operand,
    '>=' => value >= operand,
    '<' => value < operand,
    '<=' => value <= operand,
    '<>' || '!=' => value != operand,
    '=' || '==' => value == operand,
    _ => false,
  };
}

bool _matchesBool(bool value, String operator, bool operand) {
  return switch (operator) {
    '<>' || '!=' => value != operand,
    '=' || '==' => value == operand,
    _ => false,
  };
}

bool _matchesString(String value, String operator, String operand) {
  final comparison = value.compareTo(operand);
  return switch (operator) {
    '>' => comparison > 0,
    '>=' => comparison >= 0,
    '<' => comparison < 0,
    '<=' => comparison <= 0,
    '<>' || '!=' => comparison != 0,
    '=' || '==' => comparison == 0,
    _ => false,
  };
}
