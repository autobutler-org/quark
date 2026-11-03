/// [rows] as CSV text, one line per row. A field is quoted when it holds a
/// comma, a quote, a line break or a leading space, with quotes doubled.
String csvFromRows(List<List<String>> rows) =>
    rows.map((row) => row.map(_csvField).join(',')).join('\n');

String _csvField(String value) =>
    value.contains(RegExp(r'[",\r\n]')) || value.startsWith(' ')
    ? '"${value.replaceAll('"', '""')}"'
    : value;
