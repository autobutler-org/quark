// Tests for DataSheetController.exportCsv() — covers #1020.
//
// RFC-4180 rules enforced:
//   - Fields containing commas, double-quotes, or newlines MUST be enclosed
//     in double-quotes.
//   - A double-quote inside a quoted field MUST be escaped as "".
//   - Rows are separated by \n (LF). This implementation uses LF, not CRLF,
//     which is a known deviation from strict RFC-4180 — tests document that
//     choice intentionally.
//
// Export → import round trips live in import_test.dart.

import 'package:flutter_test/flutter_test.dart';

import '../support/sheet.dart';

void main() {
  group('exportCsv', () {
    for (final (label, rows, csv) in const [
      // ── Basic structure ──────────────────────────────────────────────────
      ('empty table produces empty string', <List<String>>[], ''),
      (
        'single cell, single row',
        [
          ['hello'],
        ],
        'hello',
      ),
      (
        'multiple rows are joined by newline',
        [
          ['a', 'b'],
          ['c', 'd'],
        ],
        'a,b\nc,d',
      ),
      // 3 columns → 2 commas → ",,"
      (
        'all-empty row produces the correct number of commas',
        [
          ['', '', ''],
        ],
        ',,',
      ),
      // ── Quoting / escaping ───────────────────────────────────────────────
      (
        'cell value containing a comma is quoted',
        [
          ['a,b'],
        ],
        '"a,b"',
      ),
      // RFC-4180: enclose in quotes, escape inner " as ""
      (
        'cell value containing a double-quote is quoted and the quote escaped',
        [
          [r'say "hi"'],
        ],
        '"say ""hi"""',
      ),
      (
        'cell value containing a newline is quoted',
        [
          ['line1\nline2'],
        ],
        '"line1\nline2"',
      ),
      (
        'cell value containing both a comma and a double-quote',
        [
          ['a,"b"'],
        ],
        '"a,""b"""',
      ),
      (
        'cell value that is a bare double-quote character',
        [
          ['"'],
        ],
        '""""',
      ),
      (
        'cell value containing only a comma',
        [
          [','],
        ],
        '","',
      ),
      (
        'leading and trailing whitespace is preserved without extra quoting',
        [
          ['  hello  '],
        ],
        '  hello  ',
      ),
      (
        'numeric strings are not quoted',
        [
          ['42', '3.14', '-7'],
        ],
        '42,3.14,-7',
      ),
      // ── Mixed rows ───────────────────────────────────────────────────────
      (
        'mix of plain and quoted fields on the same row',
        [
          ['plain', 'has,comma', 'also plain'],
        ],
        'plain,"has,comma",also plain',
      ),
      (
        'multi-row with some quoted fields',
        [
          ['Name', 'Value'],
          ['Alice', '100'],
          ['Bob', 'hello, world'],
        ],
        'Name,Value\nAlice,100\nBob,"hello, world"',
      ),
    ]) {
      test(label, () {
        final c = sheetOf(rows);
        addTearDown(c.dispose);
        expect(c.exportCsv(), csv);
      });
    }
  });
}
