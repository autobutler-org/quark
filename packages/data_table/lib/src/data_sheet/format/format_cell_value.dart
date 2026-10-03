import '../../models/cell_format.dart';

/// The day spreadsheet serial dates count from: serial 1 is 1899-12-31, as in
/// Google Sheets and Excel.
final DateTime _serialEpoch = DateTime.utc(1899, 12, 30);

/// [value] as a cell with [format] displays it.
///
/// Only the display changes: [value] is what the cell holds or its formula
/// computed, and stays the value every formula, sort and filter reads. A value
/// that is not a finite number — text, a blank, an error such as `#DIV/0!` —
/// shows as it is under every format, as does a number too large for fixed
/// notation.
///
/// ```dart
/// formatCellValue('1234.5', const CellFormat(
///   numberFormat: CellNumberFormat.currency,
/// )); // $1,234.50
/// ```
String formatCellValue(String value, CellFormat format) {
  if (format.numberFormat == CellNumberFormat.general) return value;
  final n = double.tryParse(value.trim());
  if (n == null || !n.isFinite || n.abs() >= 1e21) return value;
  final decimals = format.effectiveDecimals;
  return switch (format.numberFormat) {
    CellNumberFormat.general => value,
    CellNumberFormat.number => _grouped(n, decimals),
    CellNumberFormat.currency => _grouped(n, decimals, prefix: r'$'),
    CellNumberFormat.percent => '${_grouped(n * 100, decimals)}%',
    CellNumberFormat.date => _serialEpoch
        .add(Duration(days: n.floor()))
        .toIso8601String()
        .substring(0, 10),
  };
}

/// [n] rounded to [decimals] places with commas between thousands, [prefix]
/// after the minus sign. A value that rounds to zero loses its sign.
String _grouped(double n, int decimals, {String prefix = ''}) {
  final fixed = n.abs().toStringAsFixed(decimals);
  final point = fixed.indexOf('.');
  final whole = point < 0 ? fixed : fixed.substring(0, point);
  final fraction = point < 0 ? '' : fixed.substring(point);
  final groups = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) groups.write(',');
    groups.write(whole[i]);
  }
  final negative = n < 0 && fixed.contains(RegExp('[1-9]'));
  return '${negative ? '-' : ''}$prefix$groups$fraction';
}
