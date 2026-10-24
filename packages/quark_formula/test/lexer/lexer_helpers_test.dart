import 'package:quark_formula/evaluation/lexer/helpers.dart';
import 'package:quark_formula/evaluation/token.dart';
import 'package:test/test.dart';

void main() {
  group('lexer helpers', () {
    test('character classification helpers behave as expected', () {
      expect(isFormulaWhitespace(' '), isTrue);
      expect(isFormulaWhitespace('A'), isFalse);

      expect(isFormulaDigit('7'), isTrue);
      expect(isFormulaDigit('x'), isFalse);

      expect(isFormulaLetter('Q'), isTrue);
      expect(isFormulaLetter('_'), isFalse);

      expect(startsFormulaWord(r'$'), isTrue);
      expect(startsFormulaWord('_'), isTrue);
      expect(startsFormulaWord('3'), isFalse);

      expect(continuesFormulaWord('3'), isTrue);
      expect(continuesFormulaWord('A'), isTrue);
      expect(continuesFormulaWord('-'), isFalse);
    });

    test('cell reference and lookahead helpers normalize formula grammar', () {
      expect(formulaMatches('<=', 1, '='), isTrue);
      expect(formulaMatches('<=', 1, '>'), isFalse);

      expect(formulaHasDigitAhead('.5', 1), isTrue);
      expect(formulaHasDigitAhead('.', 1), isFalse);

      expect(isFormulaCellReference('A1'), isTrue);
      expect(isFormulaCellReference('AA10'), isTrue);
      expect(isFormulaCellReference('A0'), isFalse);
      expect(isFormulaCellReference('1A'), isFalse);
    });

    test('number scanner parses decimals and scientific notation', () {
      final decimal = scanFormulaNumber('.75', 0);
      expect(decimal.lexeme, '.75');
      expect(decimal.nextIndex, 3);

      final scientific = scanFormulaNumber('12.5E-2+', 0);
      expect(scientific.lexeme, '12.5E-2');
      expect(scientific.nextIndex, 7);
    });

    test('string scanner unescapes doubled quotes', () {
      final result = scanFormulaString('"a""b"', 0);

      expect(result.lexeme, 'a"b');
      expect(result.nextIndex, 6);
    });

    test('word scanner identifies booleans, idents, and cell refs', () {
      final booleanResult = scanFormulaWord('true,', 0);
      expect(booleanResult.token, const TypeMatcher<Token>());
      expect(booleanResult.token.kind, TokenKind.boolean);
      expect(booleanResult.token.value, 'TRUE');
      expect(booleanResult.nextIndex, 4);

      final identResult = scanFormulaWord('sum_', 0);
      expect(identResult.token.kind, TokenKind.ident);
      expect(identResult.token.value, 'SUM_');

      final cellRefResult = scanFormulaWord(r'$b$12)', 0);
      expect(cellRefResult.token.kind, TokenKind.cellRef);
      expect(cellRefResult.token.value, 'B12');
      expect(cellRefResult.nextIndex, 5);
    });

    test('scanner helpers throw parse errors for invalid input', () {
      expect(
        () => scanFormulaNumber('1e+', 0),
        throwsA(isA<LexError>().having((error) => error.offset, 'offset', 1)),
      );

      expect(
        () => scanFormulaString('"unterminated', 0),
        throwsA(isA<LexError>()),
      );

      expect(() => scanFormulaWord(r'$foo', 0), throwsA(isA<LexError>()));
    });

    test('parseCellRef reads A1 references as zero-based (row, col)', () {
      expect(parseCellRef('A1'), (0, 0));
      expect(parseCellRef('b2'), (1, 1));
      expect(parseCellRef('Z10'), (9, 25));
      expect(parseCellRef('AA1'), (0, 26));
      for (final bad in ['', 'A', '1', 'A0', '1A', r'$A1', 'A1B']) {
        expect(parseCellRef(bad), isNull, reason: bad);
      }
    });
  });
}
