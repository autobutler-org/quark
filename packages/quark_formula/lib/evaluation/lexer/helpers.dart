import '../errors/lexer_errors.dart';
import '../token.dart';

export '../errors/lexer_errors.dart';

/// Whether [char] is whitespace between formula tokens. This file holds the character classes the lexer is built
/// from.
bool isFormulaWhitespace(String char) => char.trim().isEmpty;

bool isFormulaDigit(String char) {
  final codeUnit = char.codeUnitAt(0);
  return codeUnit >= 48 && codeUnit <= 57;
}

bool isFormulaLetter(String char) {
  final codeUnit = char.codeUnitAt(0);
  return (codeUnit >= 65 && codeUnit <= 90) ||
      (codeUnit >= 97 && codeUnit <= 122);
}

bool startsFormulaWord(String char) =>
    isFormulaLetter(char) || char == '_' || char == r'$';

bool continuesFormulaWord(String char) =>
    isFormulaLetter(char) ||
    isFormulaDigit(char) ||
    char == '_' ||
    char == r'$';

bool formulaMatches(String source, int index, String expected) =>
    index < source.length && source[index] == expected;

bool formulaHasDigitAhead(String source, int index) =>
    index < source.length && isFormulaDigit(source[index]);

bool isFormulaCellReference(String value) {
  final match = RegExp(r'^[A-Z]+[1-9][0-9]*$').firstMatch(value);
  return match != null;
}

/// Reads an A1 cell reference such as `B2`, in either case, as zero-based
/// `(row, col)`; null when [ref] is not one. A `$` is not accepted: strip it
/// first.
(int, int)? parseCellRef(String ref) {
  var splitIndex = 0;
  while (splitIndex < ref.length &&
      _isAsciiLetter(ref.codeUnitAt(splitIndex))) {
    splitIndex++;
  }
  if (splitIndex == 0 || splitIndex == ref.length) return null;

  final row = int.tryParse(ref.substring(splitIndex));
  if (row == null || row <= 0) return null;

  var column = 0;
  for (final unit in ref.substring(0, splitIndex).toUpperCase().codeUnits) {
    column = column * 26 + (unit - 64);
  }
  return (row - 1, column - 1);
}

bool _isAsciiLetter(int codeUnit) =>
    (codeUnit >= 65 && codeUnit <= 90) || (codeUnit >= 97 && codeUnit <= 122);

FormulaScanResult scanFormulaNumber(String source, int start) {
  var index = start;
  var sawDigit = false;

  while (index < source.length && isFormulaDigit(source[index])) {
    sawDigit = true;
    index++;
  }

  if (formulaMatches(source, index, '.')) {
    index++;
    while (index < source.length && isFormulaDigit(source[index])) {
      sawDigit = true;
      index++;
    }
  }

  if (!sawDigit) {
    throw LexError('Invalid number literal.', offset: start);
  }

  if (index < source.length && (source[index] == 'e' || source[index] == 'E')) {
    final exponentStart = index;
    var exponentIndex = index + 1;

    if (exponentIndex < source.length &&
        (source[exponentIndex] == '+' || source[exponentIndex] == '-')) {
      exponentIndex++;
    }

    final digitStart = exponentIndex;
    while (exponentIndex < source.length &&
        isFormulaDigit(source[exponentIndex])) {
      exponentIndex++;
    }

    if (digitStart == exponentIndex) {
      throw LexError('Invalid scientific notation.', offset: exponentStart);
    }

    index = exponentIndex;
  }

  return FormulaScanResult(source.substring(start, index), index);
}

FormulaScanResult scanFormulaString(String source, int start) {
  final buffer = StringBuffer();
  var index = start + 1;

  while (index < source.length) {
    final char = source[index];

    if (char == '"') {
      if (formulaMatches(source, index + 1, '"')) {
        buffer.write('"');
        index += 2;
        continue;
      }

      return FormulaScanResult(buffer.toString(), index + 1);
    }

    buffer.write(char);
    index++;
  }

  throw LexError('Unterminated string literal.', offset: start);
}

FormulaWordScanResult scanFormulaWord(String source, int start) {
  var index = start;
  while (index < source.length && continuesFormulaWord(source[index])) {
    index++;
  }

  final rawLexeme = source.substring(start, index);
  final normalized = rawLexeme.replaceAll(r'$', '').toUpperCase();

  if (rawLexeme.contains(r'$')) {
    if (!isFormulaCellReference(normalized)) {
      throw LexError('Invalid cell reference: $rawLexeme', offset: start);
    }

    return FormulaWordScanResult(
      Token(kind: TokenKind.cellRef, value: normalized, offset: start),
      index,
    );
  }

  if (normalized == 'TRUE' || normalized == 'FALSE') {
    return FormulaWordScanResult(
      Token(kind: TokenKind.boolean, value: normalized, offset: start),
      index,
    );
  }

  if (isFormulaCellReference(normalized)) {
    return FormulaWordScanResult(
      Token(kind: TokenKind.cellRef, value: normalized, offset: start),
      index,
    );
  }

  return FormulaWordScanResult(
    Token(kind: TokenKind.ident, value: normalized, offset: start),
    index,
  );
}

class FormulaScanResult {
  final String lexeme;
  final int nextIndex;

  FormulaScanResult(this.lexeme, this.nextIndex);
}

class FormulaWordScanResult {
  final Token token;
  final int nextIndex;

  FormulaWordScanResult(this.token, this.nextIndex);
}
