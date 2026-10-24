import 'package:data_table/src/models/data_cell.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DataCell', () {
    group('toJson', () {
      test('returns the value string', () {
        expect(DataCell('abc').toJson(), 'abc');
      });
    });

    group('fromJson', () {
      test('parses a string value', () {
        expect(DataCell.fromJson('foo').value, 'foo');
      });

      test('converts non-string to string', () {
        expect(DataCell.fromJson(42).value, '42');
      });

      test('returns empty string for null', () {
        expect(DataCell.fromJson(null).value, '');
      });
    });
  });
}
