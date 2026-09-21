import 'dart:collection';

import '../token.dart';

/// A node in a parsed formula: a literal, a cell or range reference, an operator, or a function call.
sealed class FormulaNode {
  final int offset;

  const FormulaNode({required this.offset});
}

final class NumberNode extends FormulaNode {
  final double value;

  const NumberNode({required this.value, required super.offset});
}

final class StringNode extends FormulaNode {
  final String value;

  const StringNode({required this.value, required super.offset});
}

final class BoolNode extends FormulaNode {
  final bool value;

  const BoolNode({required this.value, required super.offset});
}

final class CellRefNode extends FormulaNode {
  final String ref;

  const CellRefNode({required this.ref, required super.offset});
}

final class RangeNode extends FormulaNode {
  final String startRef;
  final String endRef;

  const RangeNode({
    required this.startRef,
    required this.endRef,
    required super.offset,
  });

  String get ref => '$startRef:$endRef';
}

final class UnaryNode extends FormulaNode {
  final TokenKind operatorKind;
  final FormulaNode operand;

  const UnaryNode({
    required this.operatorKind,
    required this.operand,
    required super.offset,
  });
}

final class BinaryNode extends FormulaNode {
  final FormulaNode left;
  final TokenKind operatorKind;
  final FormulaNode right;

  const BinaryNode({
    required this.left,
    required this.operatorKind,
    required this.right,
    required super.offset,
  });
}

final class CallNode extends FormulaNode {
  final String functionName;
  final List<FormulaNode> arguments;

  const CallNode({
    required this.functionName,
    required this.arguments,
    required super.offset,
  });
}

final class ParsedFormula {
  final FormulaNode root;
  final List<String> cellRefs;
  final List<String> rangeRefs;
  final List<String> calledFunctions;
  final bool hasRangeArgs;

  ParsedFormula({
    required this.root,
    required Iterable<String> cellRefs,
    required Iterable<String> rangeRefs,
    required Iterable<String> calledFunctions,
    required this.hasRangeArgs,
  })  : cellRefs = List.unmodifiable(LinkedHashSet<String>.from(cellRefs)),
        rangeRefs = List.unmodifiable(LinkedHashSet<String>.from(rangeRefs)),
        calledFunctions =
            List.unmodifiable(LinkedHashSet<String>.from(calledFunctions));
}
