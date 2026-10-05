import 'package:data_table/data_table.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CellFormat', () {
    test('the default format is plain and saves as an empty map', () {
      expect(CellFormat.plain.isPlain, isTrue);
      expect(CellFormat.plain.toJson(), isEmpty);
    });

    test('round-trips every field through JSON', () {
      const format = CellFormat(
        bold: true,
        italic: true,
        textColor: 0xFF0EA5E9,
        fillColor: 0x4010B981,
        align: CellAlign.center,
        numberFormat: CellNumberFormat.currency,
        decimals: 0,
      );
      final json = format.toJson();
      expect(json, {
        'bold': true,
        'italic': true,
        'textColor': 0xFF0EA5E9,
        'fillColor': 0x4010B981,
        'align': 'center',
        'numberFormat': 'currency',
        'decimals': 0,
      });
      expect(CellFormat.fromJson(json), format);
    });

    test('reads unknown or mistyped values as the default', () {
      final format = CellFormat.fromJson({
        'bold': 'yes',
        'textColor': 'red',
        'align': 'justify',
        'numberFormat': 'roman',
        'decimals': -3,
        'future': 1,
      });
      expect(format, CellFormat.plain);
    });

    test('caps decimals at the maximum', () {
      expect(
        CellFormat.fromJson({'decimals': 99}).decimals,
        CellFormat.maxDecimals,
      );
    });

    test('with* methods set and clear one field each', () {
      final format = CellFormat.plain
          .withBold(true)
          .withTextColor(0xFF000000)
          .withFillColor(0xFFFFFFFF)
          .withAlign(CellAlign.right)
          .withNumberFormat(CellNumberFormat.percent)
          .withDecimals(1);
      expect(format.bold, isTrue);
      expect(format.textColor, 0xFF000000);
      expect(format.align, CellAlign.right);
      expect(format.decimals, 1);
      final cleared = format
          .withTextColor(null)
          .withFillColor(null)
          .withAlign(null)
          .withDecimals(null);
      expect(cleared.textColor, isNull);
      expect(cleared.fillColor, isNull);
      expect(cleared.align, isNull);
      expect(cleared.decimals, isNull);
      expect(cleared.bold, isTrue);
    });
  });
}
