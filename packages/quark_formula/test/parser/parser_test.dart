import 'package:quark_formula/evaluation/lexer/lexer.dart';
import 'package:quark_formula/evaluation/parser/parser.dart';
import 'package:quark_formula/evaluation/token.dart';
import 'package:test/test.dart';

void main() {
  group('FormulaParser', () {
    test('builds AST metadata from a token stream', () {
      final parsed = FormulaParser(
        lex('=SUM(A1:B2, -C3^2, "x", FALSE) >= 10'),
      ).parse();

      expect(parsed.root, isA<BinaryNode>());

      final comparison = parsed.root as BinaryNode;
      expect(comparison.operatorKind, TokenKind.gte);
      expect(comparison.left, isA<CallNode>());
      expect(comparison.right, isA<NumberNode>());

      final call = comparison.left as CallNode;
      expect(call.functionName, 'SUM');
      expect(call.arguments, hasLength(4));
      expect(call.arguments[0], isA<RangeNode>());

      final unary = call.arguments[1] as UnaryNode;
      expect(unary.operatorKind, TokenKind.minus);
      expect(unary.operand, isA<BinaryNode>());

      final power = unary.operand as BinaryNode;
      expect(power.operatorKind, TokenKind.caret);
      expect((power.left as CellRefNode).ref, 'C3');
      expect((power.right as NumberNode).value, 2);

      expect(parsed.cellRefs, orderedEquals(['C3']));
      expect(parsed.rangeRefs, orderedEquals(['A1:B2']));
      expect(parsed.calledFunctions, orderedEquals(['SUM']));
      expect(parsed.hasRangeArgs, isTrue);
    });

    test('implements precedence with right-associative power', () {
      final parsed = parseTokens(lex('=1 + 2 * 3 ^ 4 == 163'));

      final comparison = parsed.root as BinaryNode;
      expect(comparison.operatorKind, TokenKind.eqEq);

      final addition = comparison.left as BinaryNode;
      expect(addition.operatorKind, TokenKind.plus);
      expect((addition.left as NumberNode).value, 1);

      final multiplication = addition.right as BinaryNode;
      expect(multiplication.operatorKind, TokenKind.star);
      expect((multiplication.left as NumberNode).value, 2);

      final power = multiplication.right as BinaryNode;
      expect(power.operatorKind, TokenKind.caret);
      expect((power.left as NumberNode).value, 3);
      expect((power.right as NumberNode).value, 4);
    });

    test('parses literals and grouped expressions', () {
      final stringParsed = parseTokens(lex('="hello"'));
      expect(stringParsed.root, isA<StringNode>());
      expect((stringParsed.root as StringNode).value, 'hello');

      final boolParsed = parseTokens(lex('=TRUE'));
      expect(boolParsed.root, isA<BoolNode>());
      expect((boolParsed.root as BoolNode).value, isTrue);

      final groupedParsed = parseTokens(lex('=(1 + 2) * 3'));
      final root = groupedParsed.root as BinaryNode;
      expect(root.operatorKind, TokenKind.star);
      expect(root.left, isA<BinaryNode>());
      expect(root.right, isA<NumberNode>());
    });

    test(
      'parses cell references and deduplicates metadata in encounter order',
      () {
        final parsed = parseTokens(lex('=SUM(A1, A1, B2, A1, B2) + A1'));

        expect(parsed.calledFunctions, orderedEquals(['SUM']));
        expect(parsed.cellRefs, orderedEquals(['A1', 'B2']));
        expect(parsed.rangeRefs, isEmpty);
        expect(parsed.hasRangeArgs, isFalse);
      },
    );

    test('parses nested function calls with range arguments', () {
      final parsed = parseTokens(lex('=IF(A1>0, SUM(B1:B3), MAX(C1:C3))'));

      expect(parsed.root, isA<CallNode>());
      expect(parsed.calledFunctions, orderedEquals(['IF', 'SUM', 'MAX']));
      expect(parsed.cellRefs, orderedEquals(['A1']));
      expect(parsed.rangeRefs, orderedEquals(['B1:B3', 'C1:C3']));
      expect(parsed.hasRangeArgs, isTrue);
    });

    test('makes power right associative across repeated operators', () {
      final parsed = parseTokens(lex('=2 ^ 3 ^ 4'));
      final root = parsed.root as BinaryNode;

      expect(root.operatorKind, TokenKind.caret);
      expect((root.left as NumberNode).value, 2);

      final nested = root.right as BinaryNode;
      expect(nested.operatorKind, TokenKind.caret);
      expect((nested.left as NumberNode).value, 3);
      expect((nested.right as NumberNode).value, 4);
    });

    test('makes comparison left associative', () {
      final parsed = parseTokens(lex('=1 < 2 < 3'));
      final root = parsed.root as BinaryNode;

      expect(root.operatorKind, TokenKind.lt);
      expect(root.left, isA<BinaryNode>());
      expect((root.right as NumberNode).value, 3);

      final left = root.left as BinaryNode;
      expect(left.operatorKind, TokenKind.lt);
      expect((left.left as NumberNode).value, 1);
      expect((left.right as NumberNode).value, 2);
    });

    for (final (formula, offset, message) in const [
      ('=A1:B2', 2, 'Range references are only allowed'),
      ('=foo + 1', 0, 'Expected "(" after identifier FOO'),
      ('=SUM(A1, 2', 9, 'Expected ")" after function arguments'),
      ('=SUM(A1:, 2)', 7, 'Expected cell reference after'),
      ('=SUM(A1,)', 7, 'Expected expression'),
      ('', 0, 'Expected expression'),
      ('=1 2', 2, 'Expected end of formula'),
    ]) {
      test('rejects "$formula" at $offset: $message', () {
        expect(
          () => parseTokens(lex(formula)),
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
