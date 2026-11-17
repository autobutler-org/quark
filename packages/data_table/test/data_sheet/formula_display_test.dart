import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sheet.dart';

/// A sheet holding [formula] in A1, plus a B1 that refers to it.
DataSheetController _make(String formula, {String b1 = ''}) {
  final c = sheetOf([
    [formula, b1],
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('formula result display (#4225)', () {
    test('650 - 512.40 shows 137.6', () {
      expect(_make('=650-512.40').displayValueAt(0, 0), '137.6');
    });

    test('0.1 + 0.2 shows 0.3', () {
      expect(_make('=0.1+0.2').displayValueAt(0, 0), '0.3');
    });

    test('a large integer keeps every digit', () {
      expect(_make('=1e15').displayValueAt(0, 0), '1000000000000000');
      expect(
        _make('=1234567890123456+0').displayValueAt(0, 0),
        '1234567890123456',
      );
    });

    test('a negative result rounds the same way', () {
      expect(_make('=512.40-650').displayValueAt(0, 0), '-137.6');
      expect(_make('=-51.75').displayValueAt(0, 0), '-51.75');
    });

    test('keeps at most 10 significant digits, dropping trailing zeros', () {
      expect(_make('=2/3').displayValueAt(0, 0), '0.6666666667');
      expect(_make('=21.88').displayValueAt(0, 0), '21.88');
    });

    test('a cell that refers to it computes with the full double', () {
      // 0.1 + 0.2 is 0.30000000000000004. A1 shows 0.3, but B1 still sees
      // the 4e-17; had A1 been rounded, B1 would be 0.
      final c = _make('=0.1+0.2', b1: '=(A1-0.3)*1e16');
      expect(c.displayValueAt(0, 0), '0.3');
      expect(c.displayValueAt(0, 1), '0.5551115123');
    });

    test('the stored formula is unchanged', () {
      expect(_make('=650-512.40').cellAt(0, 0).value, '=650-512.40');
    });

    test('an explicit number format formats the full value', () {
      final c = _make('=1234567.123456+0');
      expect(c.displayValueAt(0, 0), '1234567.123');
      c.applyFormat(
        const CellRange(top: 0, left: 0, bottom: 0, right: 0),
        (f) => f.withNumberFormat(CellNumberFormat.number).withDecimals(6),
      );
      expect(c.formattedValueAt(0, 0), '1,234,567.123456');
    });
  });
}
