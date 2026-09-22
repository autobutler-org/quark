import 'dart:collection';

import '../errors/lexer_errors.dart';
import '../token.dart';
import 'ast.dart';

export '../errors/lexer_errors.dart';
export 'ast.dart';

/// Parses a token stream into a formula tree, with the cells, ranges and functions it refers to. Throws a
/// [LexError] when the tokens do not form a formula.
ParsedFormula parseTokens(Iterable<Token> tokens) =>
    FormulaParser(tokens).parse();

class FormulaParser {
  final Iterator<Token> _tokens;
  final LinkedHashSet<String> _cellRefs = LinkedHashSet<String>();
  final LinkedHashSet<String> _rangeRefs = LinkedHashSet<String>();
  final LinkedHashSet<String> _calledFunctions = LinkedHashSet<String>();

  Token _current = Token(kind: TokenKind.eof, offset: 0);
  int _functionArgumentDepth = 0;
  bool _hasRangeArgs = false;

  FormulaParser(Iterable<Token> tokens) : _tokens = tokens.iterator {
    _advance();
  }

  ParsedFormula parse() {
    final root = _parseComparison();
    _expect(TokenKind.eof, 'Expected end of formula.');
    return ParsedFormula(
      root: root,
      cellRefs: _cellRefs,
      rangeRefs: _rangeRefs,
      calledFunctions: _calledFunctions,
      hasRangeArgs: _hasRangeArgs,
    );
  }

  void _advance() {
    if (_tokens.moveNext()) {
      _current = _tokens.current;
      return;
    }

    _current = Token(kind: TokenKind.eof, offset: _current.offset);
  }

  bool _check(TokenKind kind) => _current.kind == kind;

  bool _match(TokenKind kind) {
    if (!_check(kind)) {
      return false;
    }

    _advance();
    return true;
  }

  Token _expect(TokenKind kind, String message) {
    if (!_check(kind)) {
      _error(message, _current.offset);
    }

    final token = _current;
    _advance();
    return token;
  }

  Never _error(String message, int offset) {
    throw LexError(message, offset: offset);
  }

  FormulaNode _parseComparison() {
    var left = _parseAddition();

    while (_isComparisonOperator(_current.kind)) {
      final operator = _current;
      _advance();
      final right = _parseAddition();
      left = BinaryNode(
        left: left,
        operatorKind: operator.kind,
        right: right,
        offset: operator.offset,
      );
    }

    return left;
  }

  FormulaNode _parseAddition() {
    var left = _parseTerm();

    while (
        _current.kind == TokenKind.plus || _current.kind == TokenKind.minus) {
      final operator = _current;
      _advance();
      final right = _parseTerm();
      left = BinaryNode(
        left: left,
        operatorKind: operator.kind,
        right: right,
        offset: operator.offset,
      );
    }

    return left;
  }

  FormulaNode _parseTerm() {
    var left = _parseUnary();

    while (_current.kind == TokenKind.star ||
        _current.kind == TokenKind.slash ||
        _current.kind == TokenKind.percent) {
      final operator = _current;
      _advance();
      final right = _parseUnary();
      left = BinaryNode(
        left: left,
        operatorKind: operator.kind,
        right: right,
        offset: operator.offset,
      );
    }

    return left;
  }

  FormulaNode _parseUnary() {
    if (_current.kind == TokenKind.plus || _current.kind == TokenKind.minus) {
      final operator = _current;
      _advance();
      return UnaryNode(
        operatorKind: operator.kind,
        operand: _parseUnary(),
        offset: operator.offset,
      );
    }

    return _parsePower();
  }

  FormulaNode _parsePower() {
    final left = _parsePrimary();

    if (_current.kind != TokenKind.caret) {
      return left;
    }

    final operator = _current;
    _advance();
    final right = _parseUnary();
    return BinaryNode(
      left: left,
      operatorKind: operator.kind,
      right: right,
      offset: operator.offset,
    );
  }

  FormulaNode _parsePrimary() {
    switch (_current.kind) {
      case TokenKind.number:
        final token = _current;
        _advance();
        final value = token.asNumber();
        if (value == null) {
          _error('Invalid number literal.', token.offset);
        }
        return NumberNode(value: value, offset: token.offset);
      case TokenKind.string:
        final token = _current;
        _advance();
        return StringNode(value: token.value, offset: token.offset);
      case TokenKind.boolean:
        final token = _current;
        _advance();
        return BoolNode(value: token.value == 'TRUE', offset: token.offset);
      case TokenKind.cellRef:
        return _parseCellOrRange();
      case TokenKind.ident:
        return _parseCall();
      case TokenKind.lparen:
        _advance();
        final expression = _parseComparison();
        _expect(TokenKind.rparen, 'Expected ")" after expression.');
        return expression;
      case TokenKind.eof:
        _error('Expected expression.', _current.offset);
      default:
        _error('Expected expression.', _current.offset);
    }
  }

  FormulaNode _parseCellOrRange() {
    final start = _expect(TokenKind.cellRef, 'Expected cell reference.');

    if (!_check(TokenKind.colon)) {
      _cellRefs.add(start.value);
      return CellRefNode(ref: start.value, offset: start.offset);
    }

    if (_functionArgumentDepth == 0) {
      _error('Range references are only allowed inside function arguments.',
          _current.offset);
    }

    _advance();
    final end =
        _expect(TokenKind.cellRef, 'Expected cell reference after ":".');
    final rangeRef = '${start.value}:${end.value}';
    _rangeRefs.add(rangeRef);
    _hasRangeArgs = true;
    return RangeNode(
        startRef: start.value, endRef: end.value, offset: start.offset);
  }

  FormulaNode _parseCall() {
    final ident = _expect(TokenKind.ident, 'Expected function name.');

    if (!_check(TokenKind.lparen)) {
      _error('Expected "(" after identifier ${ident.value}.', ident.offset);
    }

    _calledFunctions.add(ident.value);
    _advance();

    final arguments = <FormulaNode>[];
    _functionArgumentDepth++;
    try {
      if (!_check(TokenKind.rparen)) {
        while (true) {
          arguments.add(_parseComparison());
          if (!_match(TokenKind.comma)) {
            break;
          }
        }
      }
    } finally {
      _functionArgumentDepth--;
    }

    _expect(TokenKind.rparen, 'Expected ")" after function arguments.');
    return CallNode(
      functionName: ident.value,
      arguments: List.unmodifiable(arguments),
      offset: ident.offset,
    );
  }

  bool _isComparisonOperator(TokenKind kind) {
    return kind == TokenKind.eqEq ||
        kind == TokenKind.neq ||
        kind == TokenKind.lt ||
        kind == TokenKind.lte ||
        kind == TokenKind.gt ||
        kind == TokenKind.gte;
  }
}
