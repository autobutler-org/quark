import 'dart:math' as math;

import '../parser/ast.dart';
import '../token.dart';
import 'builtins.dart';
import 'values.dart';

/// Reads another cell's value while a formula is evaluated, so the evaluator never touches the sheet directly.
typedef CellAccessor = FormulaValue Function(int row, int col);

FormulaValue evaluate(
  ParsedFormula formula,
  CellAccessor cellAccessor, {
  int originRow = 0,
  int originCol = 0,
  Map<String, BuiltinFn>? builtins,
}) {
  return FormulaEvaluator(
    cellAccessor: cellAccessor,
    originRow: originRow,
    originCol: originCol,
    builtins: builtins,
  ).evaluate(formula.root);
}

class FormulaEvaluator {
  final CellAccessor _cellAccessor;
  final Map<String, BuiltinFn> _builtins;
  final int originRow;
  final int originCol;

  FormulaEvaluator({
    required CellAccessor cellAccessor,
    this.originRow = 0,
    this.originCol = 0,
    Map<String, BuiltinFn>? builtins,
  })  : _cellAccessor = cellAccessor,
        _builtins = builtins ?? builtinFunctions;

  FormulaValue evaluate(FormulaNode node) {
    return switch (node) {
      NumberNode(:final value) => NumberValue(value),
      StringNode(:final value) => StringValue(value),
      BoolNode(:final value) => BoolValue(value),
      CellRefNode(:final ref) => _readCell(ref),
      RangeNode() =>
        valueError('Range values can only be consumed by functions'),
      UnaryNode() => _evaluateUnary(node),
      BinaryNode() => _evaluateBinary(node),
      CallNode() => _evaluateCall(node),
    };
  }

  FormulaValue _evaluateUnary(UnaryNode node) {
    final operand = evaluate(node.operand);
    if (operand is ErrorValue) {
      return operand;
    }
    if (operand is! NumberValue) {
      return valueError('Unary operators expect numeric operands');
    }
    return switch (node.operatorKind) {
      TokenKind.plus => NumberValue(operand.value),
      TokenKind.minus => NumberValue(-operand.value),
      _ => valueError('Unsupported unary operator ${node.operatorKind.name}'),
    };
  }

  FormulaValue _evaluateBinary(BinaryNode node) {
    final left = evaluate(node.left);
    if (left is ErrorValue) {
      return left;
    }
    final right = evaluate(node.right);
    if (right is ErrorValue) {
      return right;
    }

    return switch (node.operatorKind) {
      TokenKind.plus => _numericBinary(left, right, (a, b) => a + b),
      TokenKind.minus => _numericBinary(left, right, (a, b) => a - b),
      TokenKind.star => _numericBinary(left, right, (a, b) => a * b),
      TokenKind.slash => _divide(left, right),
      TokenKind.percent => _modulo(left, right),
      TokenKind.caret => _numericBinary(left, right, _pow),
      TokenKind.eqEq ||
      TokenKind.neq ||
      TokenKind.lt ||
      TokenKind.lte ||
      TokenKind.gt ||
      TokenKind.gte =>
        _compareValues(left, right, node.operatorKind),
      _ => valueError('Unsupported binary operator ${node.operatorKind.name}'),
    };
  }

  FormulaValue _evaluateCall(CallNode node) {
    final builtin = _builtins[node.functionName];
    if (builtin == null) {
      return nameError('Unknown function ${node.functionName}');
    }

    final arguments = <ResolvedArgument>[];
    for (final argument in node.arguments) {
      if (argument case RangeNode(:final startRef, :final endRef)) {
        final rangeValues = _resolveRange(startRef, endRef);
        for (final value in rangeValues) {
          if (value is ErrorValue) {
            return value;
          }
        }
        arguments.add(RangeArgument(rangeValues));
        continue;
      }
      arguments.add(ScalarArgument(evaluate(argument)));
    }
    return builtin(arguments);
  }

  FormulaValue _numericBinary(
    FormulaValue left,
    FormulaValue right,
    double Function(double left, double right) operation,
  ) {
    if (left is! NumberValue || right is! NumberValue) {
      return valueError('Arithmetic operators expect numbers');
    }
    return NumberValue(operation(left.value, right.value));
  }

  FormulaValue _divide(FormulaValue left, FormulaValue right) {
    if (left is! NumberValue || right is! NumberValue) {
      return valueError('Arithmetic operators expect numbers');
    }
    if (right.value == 0) {
      return div0Error();
    }
    return NumberValue(left.value / right.value);
  }

  FormulaValue _modulo(FormulaValue left, FormulaValue right) {
    if (left is! NumberValue || right is! NumberValue) {
      return valueError('Arithmetic operators expect numbers');
    }
    if (right.value == 0) {
      return div0Error();
    }
    return NumberValue(left.value % right.value);
  }

  FormulaValue _compareValues(
    FormulaValue left,
    FormulaValue right,
    TokenKind operatorKind,
  ) {
    if (left.runtimeType != right.runtimeType) {
      return valueError('Comparison operands must have the same type');
    }

    late final int comparison;
    if (left is NumberValue && right is NumberValue) {
      comparison = left.value.compareTo(right.value);
    } else if (left is StringValue && right is StringValue) {
      comparison = left.value.compareTo(right.value);
    } else if (left is BoolValue && right is BoolValue) {
      comparison = left.value == right.value ? 0 : (left.value ? 1 : -1);
    } else {
      return valueError('Unsupported comparison operands');
    }

    return BoolValue(
      switch (operatorKind) {
        TokenKind.eqEq => comparison == 0,
        TokenKind.neq => comparison != 0,
        TokenKind.lt => comparison < 0,
        TokenKind.lte => comparison <= 0,
        TokenKind.gt => comparison > 0,
        TokenKind.gte => comparison >= 0,
        _ => false,
      },
    );
  }

  FormulaValue _readCell(String ref) {
    final coordinates = _parseCellRef(ref);
    if (coordinates == null) {
      return refError('Invalid cell reference $ref');
    }
    return _cellAccessor(coordinates.$1, coordinates.$2);
  }

  List<FormulaValue> _resolveRange(String startRef, String endRef) {
    final start = _parseCellRef(startRef);
    final end = _parseCellRef(endRef);
    if (start == null || end == null) {
      return [refError('Invalid range reference $startRef:$endRef')];
    }

    final rowStart = start.$1 < end.$1 ? start.$1 : end.$1;
    final rowEnd = start.$1 > end.$1 ? start.$1 : end.$1;
    final colStart = start.$2 < end.$2 ? start.$2 : end.$2;
    final colEnd = start.$2 > end.$2 ? start.$2 : end.$2;

    final values = <FormulaValue>[];
    for (var row = rowStart; row <= rowEnd; row++) {
      for (var col = colStart; col <= colEnd; col++) {
        values.add(_cellAccessor(row, col));
      }
    }
    return values;
  }

  (int, int)? _parseCellRef(String ref) {
    var splitIndex = 0;
    while (splitIndex < ref.length && _isAlpha(ref.codeUnitAt(splitIndex))) {
      splitIndex++;
    }
    if (splitIndex == 0 || splitIndex == ref.length) {
      return null;
    }

    final columnText = ref.substring(0, splitIndex);
    final rowText = ref.substring(splitIndex);
    final row = int.tryParse(rowText);
    if (row == null || row <= 0) {
      return null;
    }

    var column = 0;
    for (final rune in columnText.runes) {
      final upper = String.fromCharCode(rune).toUpperCase().codeUnitAt(0);
      if (!_isAlpha(upper)) {
        return null;
      }
      column = column * 26 + (upper - 64);
    }

    return (row - 1, column - 1);
  }

  bool _isAlpha(int codeUnit) =>
      codeUnit >= 65 && codeUnit <= 90 || codeUnit >= 97 && codeUnit <= 122;

  double _pow(double left, double right) => math.pow(left, right).toDouble();
}
