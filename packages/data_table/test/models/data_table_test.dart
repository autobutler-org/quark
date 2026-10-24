import 'package:data_table/src/models/data_cell.dart';
import 'package:data_table/src/models/data_row.dart';
import 'package:data_table/src/models/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataTable', () {
    group('toJson', () {
      test('serializes rows', () {
        final table = DataTable([
          DataRow([DataCell('1'), DataCell('2')]),
          DataRow([DataCell('3'), DataCell('4')]),
        ]);
        expect(table.toJson(), {
          'rows': [
            ['1', '2'],
            ['3', '4'],
          ],
        });
      });

      test('serializes empty table', () {
        expect(DataTable([]).toJson(), {'rows': []});
      });
    });

    group('fromJson', () {
      test('parses rows from JSON', () {
        final table = DataTable.fromJson({
          'rows': [
            ['a', 'b'],
            ['c', 'd'],
          ],
        });
        expect(table.rows.length, 2);
        expect(table.rows[0].cells[0].value, 'a');
        expect(table.rows[1].cells[1].value, 'd');
      });

      test('returns empty table when rows key is missing', () {
        final table = DataTable.fromJson({});
        expect(table.rows, isEmpty);
      });

      test('returns empty table when rows is null', () {
        final table = DataTable.fromJson({'rows': null});
        expect(table.rows, isEmpty);
      });
    });
  });
}
