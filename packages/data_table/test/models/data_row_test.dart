import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataRow', () {
    group('toJson', () {
      test('returns list of cell values', () {
        final row = DataRow([DataCell('foo'), DataCell('bar')]);
        expect(row.toJson(), ['foo', 'bar']);
      });
    });

    group('fromJson', () {
      test('parses list of strings into cells', () {
        final row = DataRow.fromJson(['one', 'two', 'three']);
        expect(row.cells.length, 3);
        expect(row.cells[0].value, 'one');
        expect(row.cells[1].value, 'two');
        expect(row.cells[2].value, 'three');
      });

      test('converts non-string entries to strings', () {
        final row = DataRow.fromJson([1, 2]);
        expect(row.cells[0].value, '1');
        expect(row.cells[1].value, '2');
      });

      test('handles null entries as empty strings', () {
        final row = DataRow.fromJson([null]);
        expect(row.cells[0].value, '');
      });
    });
  });
}
