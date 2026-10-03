import 'package:quark_formula/evaluation/evaluation.dart';
import 'package:test/test.dart';

void main() {
  DataSheetInterpreter makeInterpreter() => DataSheetInterpreter();

  /// Helper: builds a fixed-size cell grid from [cells], where each entry is
  /// `(row, col, rawValue)`.
  Map<(int, int), FormulaValue> interpret(
    int rows,
    int cols,
    Map<(int, int), String> cells,
  ) {
    return makeInterpreter().interpretSheet(
      rows,
      cols,
      (r, c) => cells[(r, c)] ?? '',
    );
  }

  group('DataSheetInterpreter – topological evaluation', () {
    test('evaluates independent formula cells', () {
      final results = interpret(1, 2, {
        (0, 0): '3',
        (0, 1): '=A1 * 2',
      });

      expect(results[(0, 1)], const NumberValue(6));
    });

    test('evaluates a chain of dependencies in correct order', () {
      // A1=1, B1==A1+1, C1==B1+1 → A1=1, B1=2, C1=3
      final results = interpret(1, 3, {
        (0, 0): '1',
        (0, 1): '=A1 + 1',
        (0, 2): '=B1 + 1',
      });

      expect(results[(0, 1)], const NumberValue(2));
      expect(results[(0, 2)], const NumberValue(3));
    });

    test('evaluates diamond dependency correctly', () {
      // A1=10, B1==A1+1, C1==A1+2, D1==B1+C1 → D1=23
      final results = interpret(1, 4, {
        (0, 0): '10',
        (0, 1): '=A1 + 1',
        (0, 2): '=A1 + 2',
        (0, 3): '=B1 + C1',
      });

      expect(results[(0, 3)], const NumberValue(23));
    });

    test('literal-only sheet returns empty map', () {
      final results = interpret(2, 2, {
        (0, 0): '1',
        (0, 1): 'hello',
        (1, 0): 'true',
        (1, 1): '',
      });

      expect(results, isEmpty);
    });

    test('formula referencing an empty cell treats it as blank', () {
      final results = interpret(1, 2, {
        (0, 1): '=A1',
      });

      expect(results[(0, 1)], blankValue);
    });
  });

  group('DataSheetInterpreter – cycle detection', () {
    test('direct self-reference is marked as circular error', () {
      // A1 = =A1
      final results = interpret(1, 1, {(0, 0): '=A1'});

      expect(
        results[(0, 0)],
        const ErrorValue('#REF!', 'Circular reference'),
      );
    });

    test('two-cell mutual reference marks both cells as circular', () {
      // A1==B1, B1==A1
      final results = interpret(1, 2, {
        (0, 0): '=B1',
        (0, 1): '=A1',
      });

      expect(results[(0, 0)], const ErrorValue('#REF!', 'Circular reference'));
      expect(results[(0, 1)], const ErrorValue('#REF!', 'Circular reference'));
    });

    test('three-cell cycle marks all members as circular', () {
      // A1→B1→C1→A1
      final results = interpret(1, 3, {
        (0, 0): '=C1',
        (0, 1): '=A1',
        (0, 2): '=B1',
      });

      expect(results[(0, 0)], const ErrorValue('#REF!', 'Circular reference'));
      expect(results[(0, 1)], const ErrorValue('#REF!', 'Circular reference'));
      expect(results[(0, 2)], const ErrorValue('#REF!', 'Circular reference'));
    });

    test('cell outside the cycle that depends on a cycle member gets error',
        () {
      // A1==A1 (cycle), B1==A1 (depends on cycle)
      final results = interpret(1, 2, {
        (0, 0): '=A1',
        (0, 1): '=A1 + 1',
      });

      expect(results[(0, 0)], const ErrorValue('#REF!', 'Circular reference'));
      // B1's result is an ErrorValue because the accessor returns the
      // pre-assigned circular error for A1.
      expect(results[(0, 1)], isA<ErrorValue>());
    });

    test('acyclic cells coexist with a separate cycle in the same sheet', () {
      // A1==A1 (cycle), B1=2, C1==B1*3 (acyclic chain)
      final results = interpret(1, 3, {
        (0, 0): '=A1',
        (0, 1): '2',
        (0, 2): '=B1 * 3',
      });

      expect(results[(0, 0)], const ErrorValue('#REF!', 'Circular reference'));
      expect(results[(0, 2)], const NumberValue(6));
    });
  });

  group('DataSheetInterpreter – range dependencies', () {
    test('SUM range is evaluated correctly', () {
      // C2 (1,2) = =SUM(A1:B2), where A1:B2 = (0,0)=1, (0,1)=2, (1,0)=3, (1,1)=4
      // Formula cell (1,2) is outside the range, so no self-reference.
      final results = interpret(2, 3, {
        (0, 0): '1',
        (0, 1): '2',
        (1, 0): '3',
        (1, 1): '4',
        (1, 2): '=SUM(A1:B2)',
      });

      expect(results[(1, 2)], const NumberValue(10));
    });
  });

  group('DataSheetInterpreter – parse errors', () {
    test('report the reason in words, not the exception', () {
      final results = interpret(1, 1, {(0, 0): '=1 + !'});
      final error = results[(0, 0)];
      expect(error, isA<ErrorValue>());
      error as ErrorValue;
      expect(error.code, '#VALUE!');
      expect(
          error.message, "Couldn't read the formula: Unexpected character: !");
    });
  });
}
