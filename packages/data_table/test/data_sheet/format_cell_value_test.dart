import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

String _fmt(String value, CellNumberFormat format, [int? decimals]) =>
    formatCellValue(
      value,
      CellFormat(numberFormat: format, decimals: decimals),
    );

void main() {
  group('formatCellValue', () {
    test('general shows the value untouched', () {
      expect(_fmt('1234.5', CellNumberFormat.general), '1234.5');
      expect(_fmt('hello', CellNumberFormat.general), 'hello');
    });

    test('number groups thousands with two decimals by default', () {
      expect(_fmt('1234.5', CellNumberFormat.number), '1,234.50');
      expect(_fmt('1234567', CellNumberFormat.number, 0), '1,234,567');
      expect(_fmt('-0.004', CellNumberFormat.number), '0.00');
      expect(_fmt('-1234.567', CellNumberFormat.number, 1), '-1,234.6');
      expect(_fmt(' 42 ', CellNumberFormat.number), '42.00');
    });

    test('currency puts the sign before the dollar', () {
      expect(_fmt('1234.5', CellNumberFormat.currency), r'$1,234.50');
      expect(_fmt('-3', CellNumberFormat.currency), r'-$3.00');
      expect(_fmt('999.999', CellNumberFormat.currency, 0), r'$1,000');
    });

    test('percent multiplies by 100', () {
      expect(_fmt('0.25', CellNumberFormat.percent), '25.00%');
      expect(_fmt('0.125', CellNumberFormat.percent, 1), '12.5%');
      expect(_fmt('1.5', CellNumberFormat.percent, 0), '150%');
    });

    test('date reads a spreadsheet serial day', () {
      expect(_fmt('45658', CellNumberFormat.date), '2025-01-01');
      expect(_fmt('45658.75', CellNumberFormat.date), '2025-01-01');
      expect(_fmt('1', CellNumberFormat.date), '1899-12-31');
    });

    test('text, blanks and errors show as they are under every format', () {
      for (final format in CellNumberFormat.values) {
        expect(_fmt('apples', format), 'apples');
        expect(_fmt('', format), '');
        expect(_fmt('#DIV/0!', format), '#DIV/0!');
        expect(_fmt('TRUE', format), 'TRUE');
      }
    });

    test('numbers too large for fixed notation show as they are', () {
      expect(_fmt('1e300', CellNumberFormat.currency), '1e300');
      expect(_fmt('NaN', CellNumberFormat.number), 'NaN');
    });
  });
}
