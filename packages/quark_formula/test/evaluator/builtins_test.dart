import 'package:quark_formula/evaluation/evaluation.dart';
import 'package:test/test.dart';

void main() {
  group('builtinFunctions', () {
    ScalarArgument n(double value) => ScalarArgument(NumberValue(value));
    ScalarArgument s(String value) => ScalarArgument(StringValue(value));
    ScalarArgument b(bool value) => ScalarArgument(BoolValue(value));
    RangeArgument range(List<FormulaValue> values) => RangeArgument(values);

    final cases = <(String, List<ResolvedArgument>, FormulaValue)>[
      (
        'SUM',
        [
          n(2),
          range([const NumberValue(3), blankValue, const NumberValue(5)]),
        ],
        const NumberValue(10),
      ),
      (
        'AVERAGE',
        [
          range([const NumberValue(2), const NumberValue(4)]),
        ],
        const NumberValue(3),
      ),
      (
        'MIN',
        [
          range([const NumberValue(2), const NumberValue(-1)]),
        ],
        const NumberValue(-1),
      ),
      (
        'MAX',
        [
          range([const NumberValue(2), const NumberValue(9)]),
        ],
        const NumberValue(9),
      ),
      ('ABS', [n(-3)], const NumberValue(3)),
      ('ROUND', [n(3.14159), n(2)], const NumberValue(3.14)),
      ('FLOOR', [n(3.9)], const NumberValue(3)),
      ('CEILING', [n(3.1)], const NumberValue(4)),
      ('MOD', [n(10), n(4)], const NumberValue(2)),
      ('POWER', [n(2), n(5)], const NumberValue(32)),
      ('SQRT', [n(81)], const NumberValue(9)),
      ('CONCAT', [s('a'), n(2), b(true)], const StringValue('a2.0TRUE')),
      ('LEN', [s('hello')], const NumberValue(5)),
      ('UPPER', [s('hello')], const StringValue('HELLO')),
      ('LOWER', [s('HELLO')], const StringValue('hello')),
      ('TRIM', [s('  hi   there  ')], const StringValue('hi there')),
      ('LEFT', [s('hello'), n(2)], const StringValue('he')),
      ('RIGHT', [s('hello'), n(2)], const StringValue('lo')),
      ('MID', [s('hello'), n(2), n(3)], const StringValue('ell')),
      ('FIND', [s('th'), s('hi there')], const NumberValue(4)),
      (
        'SUBSTITUTE',
        [s('foo foo'), s('foo'), s('bar'), n(2)],
        const StringValue('foo bar'),
      ),
      ('IF', [b(true), s('yes'), s('no')], const StringValue('yes')),
      (
        'AND',
        [
          b(true),
          range([const BoolValue(true), const BoolValue(false)]),
        ],
        const BoolValue(false),
      ),
      (
        'OR',
        [
          b(false),
          range([const BoolValue(false), const BoolValue(true)]),
        ],
        const BoolValue(true),
      ),
      ('NOT', [b(false)], const BoolValue(true)),
      (
        'IFERROR',
        [ScalarArgument(nameError()), s('fallback')],
        const StringValue('fallback'),
      ),
      ('ISBLANK', [ScalarArgument(blankValue)], const BoolValue(true)),
      ('ISNUMBER', [n(1)], const BoolValue(true)),
      ('ISTEXT', [s('x')], const BoolValue(true)),
      (
        'COUNT',
        [
          n(1),
          range([const NumberValue(2), const StringValue('x')]),
        ],
        const NumberValue(2),
      ),
      (
        'COUNTA',
        [
          range([blankValue, const NumberValue(2), const StringValue('x')]),
        ],
        const NumberValue(2),
      ),
      (
        'COUNTIF',
        [
          range([
            const NumberValue(1),
            const NumberValue(3),
            const NumberValue(5),
          ]),
          s('>2'),
        ],
        const NumberValue(2),
      ),
    ];

    for (final (name, args, expected) in cases) {
      test(name, () {
        final builtin = builtinFunctions[name];
        expect(builtin, isNotNull, reason: '$name should be registered');
        expect(builtin!(args), expected);
      });
    }
  });
}
