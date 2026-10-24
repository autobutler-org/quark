import 'package:quark_formula/evaluation/lexer/lexer.dart';
import 'package:quark_formula/evaluation/token.dart';
import 'package:test/test.dart';

void main() {
  group('lex', () {
    test('tokenizes a representative formula and emits eof', () {
      final tokens = lex(
        '=SUM(\$a\$1:B2, "he""llo", true, 1.25E+3) >= 5',
      ).toList();

      expect(
        tokens,
        equals([
          Token(kind: TokenKind.ident, value: 'SUM', offset: 0),
          Token(kind: TokenKind.lparen, offset: 3),
          Token(kind: TokenKind.cellRef, value: 'A1', offset: 4),
          Token(kind: TokenKind.colon, offset: 8),
          Token(kind: TokenKind.cellRef, value: 'B2', offset: 9),
          Token(kind: TokenKind.comma, offset: 11),
          Token(kind: TokenKind.string, value: 'he"llo', offset: 13),
          Token(kind: TokenKind.comma, offset: 22),
          Token(kind: TokenKind.boolean, value: 'TRUE', offset: 24),
          Token(kind: TokenKind.comma, offset: 28),
          Token(kind: TokenKind.number, value: '1.25E+3', offset: 30),
          Token(kind: TokenKind.rparen, offset: 37),
          Token(kind: TokenKind.gte, offset: 39),
          Token(kind: TokenKind.number, value: '5', offset: 42),
          Token(kind: TokenKind.eof, offset: 43),
        ]),
      );
    });

    test('skips whitespace and uppercases identifiers', () {
      final tokens = lex('  foo + false ').toList();

      expect(
        tokens,
        equals([
          Token(kind: TokenKind.ident, value: 'FOO', offset: 2),
          Token(kind: TokenKind.plus, offset: 6),
          Token(kind: TokenKind.boolean, value: 'FALSE', offset: 8),
          Token(kind: TokenKind.eof, offset: 14),
        ]),
      );
    });

    test('supports scientific notation and leading-dot decimals', () {
      final tokens = lex('.5 + 2e3').toList();

      expect(
        tokens,
        equals([
          Token(kind: TokenKind.number, value: '.5', offset: 0),
          Token(kind: TokenKind.plus, offset: 3),
          Token(kind: TokenKind.number, value: '2e3', offset: 5),
          Token(kind: TokenKind.eof, offset: 8),
        ]),
      );
    });

    test('tokenizes each operator and delimiter with exact offsets', () {
      final tokens = lex(
        'A1:B2+3-4*5/6%7^8,(9)<=10<>11!=12==13<14>15>=16',
      ).toList();

      expect(
        tokens,
        equals([
          Token(kind: TokenKind.cellRef, value: 'A1', offset: 0),
          Token(kind: TokenKind.colon, offset: 2),
          Token(kind: TokenKind.cellRef, value: 'B2', offset: 3),
          Token(kind: TokenKind.plus, offset: 5),
          Token(kind: TokenKind.number, value: '3', offset: 6),
          Token(kind: TokenKind.minus, offset: 7),
          Token(kind: TokenKind.number, value: '4', offset: 8),
          Token(kind: TokenKind.star, offset: 9),
          Token(kind: TokenKind.number, value: '5', offset: 10),
          Token(kind: TokenKind.slash, offset: 11),
          Token(kind: TokenKind.number, value: '6', offset: 12),
          Token(kind: TokenKind.percent, offset: 13),
          Token(kind: TokenKind.number, value: '7', offset: 14),
          Token(kind: TokenKind.caret, offset: 15),
          Token(kind: TokenKind.number, value: '8', offset: 16),
          Token(kind: TokenKind.comma, offset: 17),
          Token(kind: TokenKind.lparen, offset: 18),
          Token(kind: TokenKind.number, value: '9', offset: 19),
          Token(kind: TokenKind.rparen, offset: 20),
          Token(kind: TokenKind.lte, offset: 21),
          Token(kind: TokenKind.number, value: '10', offset: 23),
          Token(kind: TokenKind.neq, offset: 25),
          Token(kind: TokenKind.number, value: '11', offset: 27),
          Token(kind: TokenKind.neq, offset: 29),
          Token(kind: TokenKind.number, value: '12', offset: 31),
          Token(kind: TokenKind.eqEq, offset: 33),
          Token(kind: TokenKind.number, value: '13', offset: 35),
          Token(kind: TokenKind.lt, offset: 37),
          Token(kind: TokenKind.number, value: '14', offset: 38),
          Token(kind: TokenKind.gt, offset: 40),
          Token(kind: TokenKind.number, value: '15', offset: 41),
          Token(kind: TokenKind.gte, offset: 43),
          Token(kind: TokenKind.number, value: '16', offset: 45),
          Token(kind: TokenKind.eof, offset: 47),
        ]),
      );
    });

    test('normalizes mixed-case identifiers booleans and cell refs', () {
      final tokens = lex(r'=sUm(aa10, fAlSe, $b$12)').toList();

      expect(
        tokens,
        equals([
          Token(kind: TokenKind.ident, value: 'SUM', offset: 0),
          Token(kind: TokenKind.lparen, offset: 3),
          Token(kind: TokenKind.cellRef, value: 'AA10', offset: 4),
          Token(kind: TokenKind.comma, offset: 8),
          Token(kind: TokenKind.boolean, value: 'FALSE', offset: 10),
          Token(kind: TokenKind.comma, offset: 15),
          Token(kind: TokenKind.cellRef, value: 'B12', offset: 17),
          Token(kind: TokenKind.rparen, offset: 22),
          Token(kind: TokenKind.eof, offset: 23),
        ]),
      );
    });

    test('tracks offsets after trimming leading equals and whitespace', () {
      final tokens = lex('=  "x" + A1').toList();

      expect(
        tokens,
        equals([
          Token(kind: TokenKind.string, value: 'x', offset: 2),
          Token(kind: TokenKind.plus, offset: 6),
          Token(kind: TokenKind.cellRef, value: 'A1', offset: 8),
          Token(kind: TokenKind.eof, offset: 10),
        ]),
      );
    });

    test('accepts empty formulas as eof-only streams', () {
      expect(lex('').toList(), equals([Token(kind: TokenKind.eof, offset: 0)]));

      expect(
        lex('   ').toList(),
        equals([Token(kind: TokenKind.eof, offset: 3)]),
      );
    });

    for (final (input, offset, message) in const [
      ('=', 0, 'Standalone ='),
      ('A1 = 2', 3, 'Standalone ='),
      (r'$foo', 0, 'Invalid cell reference'),
      ('"abc', 0, 'Unterminated string'),
      ('1e+', 1, 'Invalid scientific notation'),
      ('A1 ? B2', 3, 'Unexpected character: ?'),
      ('!TRUE', 0, 'Unexpected character: !'),
    ]) {
      test('rejects $input at $offset: $message', () {
        expect(
          () => lex(input).toList(),
          throwsA(
            isA<LexError>()
                .having((error) => error.offset, 'offset', offset)
                .having((error) => error.message, 'message', contains(message)),
          ),
        );
      });
    }
  });
}
