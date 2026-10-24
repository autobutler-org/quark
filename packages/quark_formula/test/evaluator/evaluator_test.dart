import 'package:quark_formula/evaluation/evaluation.dart';
import 'package:test/test.dart';

void main() {
  group('FormulaEvaluator', () {
    FormulaValue evaluateFormula(String source, {CellAccessor? accessor}) {
      final parsed = parseTokens(lex(source));
      return evaluate(parsed, accessor ?? (_, _) => blankValue);
    }

    test(
      'evaluates arithmetic with precedence and right-associative power',
      () {
        final value = evaluateFormula('=2 ^ 3 ^ 2 + 4 * 5 - 6 / 3');

        expect(value, const NumberValue(530));
      },
    );

    test('resolves cell references through the accessor', () {
      final calls = <(int, int)>[];
      final value = evaluateFormula(
        '=A1 + B2',
        accessor: (row, col) {
          calls.add((row, col));
          if (row == 0 && col == 0) {
            return const NumberValue(7);
          }
          if (row == 1 && col == 1) {
            return const NumberValue(5);
          }
          return blankValue;
        },
      );

      expect(value, const NumberValue(12));
      expect(calls, orderedEquals([(0, 0), (1, 1)]));
    });

    test('evaluates range-aware builtins through the accessor', () {
      final calls = <(int, int)>[];
      final value = evaluateFormula(
        '=SUM(A1:B2)',
        accessor: (row, col) {
          calls.add((row, col));
          return NumberValue((row * 2 + col + 1).toDouble());
        },
      );

      expect(value, const NumberValue(10));
      expect(calls, orderedEquals([(0, 0), (0, 1), (1, 0), (1, 1)]));
    });

    test('returns division-by-zero errors', () {
      final value = evaluateFormula('=10 / (3 - 3)');

      expect(value, div0Error());
    });

    test('returns name errors for unknown functions', () {
      final value = evaluateFormula('=DOES_NOT_EXIST(1)');

      expect(value, nameError('Unknown function DOES_NOT_EXIST'));
    });

    test('returns value errors for type mismatches', () {
      final value = evaluateFormula('=1 + "x"');

      expect(value, valueError('Arithmetic operators expect numbers'));
    });

    test('propagates circular reference hook errors from the accessor', () {
      final value = evaluateFormula(
        '=A1',
        accessor: (_, _) => refError('Circular reference'),
      );

      expect(value, refError('Circular reference'));
    });

    test(
      'returns a value error when a range is evaluated outside a function',
      () {
        final parsed = RangeNode(startRef: 'A1', endRef: 'A2', offset: 0);
        final evaluator = FormulaEvaluator(cellAccessor: (_, _) => blankValue);

        expect(
          evaluator.evaluate(parsed),
          valueError('Range values can only be consumed by functions'),
        );
      },
    );
  });
}
