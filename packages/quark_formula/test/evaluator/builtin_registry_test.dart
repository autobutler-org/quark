import 'package:quark_formula/evaluation/evaluation.dart';
import 'package:test/test.dart';

void main() {
  group('builtinRegistry', () {
    test('describes every function the evaluator can call', () {
      expect(
        builtinRegistry.map((f) => f.name).toSet(),
        builtinFunctions.keys.toSet(),
      );
      expect(
        builtinRegistry.map((f) => f.name).toSet(),
        hasLength(builtinRegistry.length),
        reason: 'names are unique',
      );
    });

    test(
      'every entry has a signature naming it and a one-line description',
      () {
        for (final function in builtinRegistry) {
          expect(function.signature, startsWith('${function.name}('));
          expect(function.signature, endsWith(')'));
          expect(function.description, isNotEmpty);
          expect(function.description, isNot(contains('\n')));
        }
      },
    );

    test('the table is the evaluator\'s table', () {
      final sum = builtinRegistry.firstWhere((f) => f.name == 'SUM');
      expect(builtinFunctions['SUM'], same(sum.function));
    });
  });

  group('builtinsMatching', () {
    List<String> names(String prefix) =>
        builtinsMatching(prefix).map((f) => f.name).toList();

    test('matches by prefix, alphabetically', () {
      expect(names('CO'), ['CONCAT', 'COUNT', 'COUNTA', 'COUNTIF']);
      expect(names('IS'), ['ISBLANK', 'ISNUMBER', 'ISTEXT']);
    });

    test('ignores case', () {
      expect(names('su'), ['SUBSTITUTE', 'SUM']);
      expect(names('Su'), names('SU'));
    });

    test('an exact name comes first', () {
      expect(names('COUNT'), ['COUNT', 'COUNTA', 'COUNTIF']);
      expect(names('IF'), ['IF', 'IFERROR']);
    });

    test('nothing matches an empty or unknown prefix', () {
      expect(names(''), isEmpty);
      expect(names('ZZ'), isEmpty);
      expect(names('SUMS'), isEmpty);
    });
  });
}
