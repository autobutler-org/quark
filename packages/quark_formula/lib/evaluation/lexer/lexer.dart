import '../token.dart';
import 'helpers.dart';

export '../errors/lexer_errors.dart';
export 'helpers.dart';

/// Splits a cell's text into formula tokens, lazily.
Iterable<Token> lex(String cellValue) sync* {
  final originalValue = cellValue;

  if (cellValue.startsWith("=")) {
    cellValue = cellValue.substring(1);
  }

  if (originalValue == '=') {
    throw LexError('Standalone = is not allowed.', offset: 0);
  }

  var index = 0;

  while (index < cellValue.length) {
    final char = cellValue[index];

    if (isFormulaWhitespace(char)) {
      index++;
      continue;
    }

    final offset = index;

    if (isFormulaDigit(char) ||
        (char == '.' && formulaHasDigitAhead(cellValue, index + 1))) {
      final result = scanFormulaNumber(cellValue, index);
      yield Token(kind: TokenKind.number, value: result.lexeme, offset: offset);
      index = result.nextIndex;
      continue;
    }

    if (char == '"') {
      final result = scanFormulaString(cellValue, index);
      yield Token(kind: TokenKind.string, value: result.lexeme, offset: offset);
      index = result.nextIndex;
      continue;
    }

    if (startsFormulaWord(char)) {
      final result = scanFormulaWord(cellValue, index);
      yield result.token;
      index = result.nextIndex;
      continue;
    }

    switch (char) {
      case ':':
        yield Token(kind: TokenKind.colon, offset: offset);
        index++;
      case '+':
        yield Token(kind: TokenKind.plus, offset: offset);
        index++;
      case '-':
        yield Token(kind: TokenKind.minus, offset: offset);
        index++;
      case '*':
        yield Token(kind: TokenKind.star, offset: offset);
        index++;
      case '/':
        yield Token(kind: TokenKind.slash, offset: offset);
        index++;
      case '%':
        yield Token(kind: TokenKind.percent, offset: offset);
        index++;
      case '^':
        yield Token(kind: TokenKind.caret, offset: offset);
        index++;
      case '(':
        yield Token(kind: TokenKind.lparen, offset: offset);
        index++;
      case ')':
        yield Token(kind: TokenKind.rparen, offset: offset);
        index++;
      case ',':
        yield Token(kind: TokenKind.comma, offset: offset);
        index++;
      case '<':
        if (formulaMatches(cellValue, index + 1, '=')) {
          yield Token(kind: TokenKind.lte, offset: offset);
          index += 2;
        } else if (formulaMatches(cellValue, index + 1, '>')) {
          yield Token(kind: TokenKind.neq, offset: offset);
          index += 2;
        } else {
          yield Token(kind: TokenKind.lt, offset: offset);
          index++;
        }
      case '>':
        if (formulaMatches(cellValue, index + 1, '=')) {
          yield Token(kind: TokenKind.gte, offset: offset);
          index += 2;
        } else {
          yield Token(kind: TokenKind.gt, offset: offset);
          index++;
        }
      case '!':
        if (formulaMatches(cellValue, index + 1, '=')) {
          yield Token(kind: TokenKind.neq, offset: offset);
          index += 2;
        } else {
          throw LexError('Unexpected character: !', offset: offset);
        }
      case '=':
        if (formulaMatches(cellValue, index + 1, '=')) {
          yield Token(kind: TokenKind.eqEq, offset: offset);
          index += 2;
        } else {
          throw LexError('Standalone = is not allowed.', offset: offset);
        }
      default:
        throw LexError('Unexpected character: $char', offset: offset);
    }
  }

  yield Token(kind: TokenKind.eof, offset: cellValue.length);
}
