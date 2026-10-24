// Tests for DataSheetController.loadFromCsv() — covers #1021.
//
// The parser follows RFC-4180:
//   - Fields MAY be enclosed in double-quotes.
//   - A double-quote inside a quoted field is escaped as "".
//   - Quoted fields may contain commas and newlines.
//   - Unquoted fields: content is taken literally up to the next comma or
//     end-of-line (RFC-4180 does NOT strip leading/trailing whitespace).

import 'package:data_table/src/data_sheet/data_sheet_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/sheet.dart';

/// Every cell of [c], row by row.
List<List<String>> _grid(DataSheetController c) => [
  for (var r = 0; r < c.rowCount; r++)
    [for (var col = 0; col < c.colCount; col++) c.cellAt(r, col).value],
];

void main() {
  group('loadFromCsv', () {
    for (final (label, csv, grid) in const [
      // ── Basic structure ──────────────────────────────────────────────────
      ('empty string produces empty table', '', <List<String>>[]),
      (
        'single cell, single row',
        'hello',
        [
          ['hello'],
        ],
      ),
      (
        'multiple columns on one row',
        'a,b,c',
        [
          ['a', 'b', 'c'],
        ],
      ),
      (
        'multiple rows separated by \\n',
        'a,b\nc,d',
        [
          ['a', 'b'],
          ['c', 'd'],
        ],
      ),
      (
        'Windows-style \\r\\n line endings are handled',
        'a,b\r\nc,d',
        [
          ['a', 'b'],
          ['c', 'd'],
        ],
      ),
      (
        'trailing newline does not produce an extra empty row',
        'a,b\nc,d\n',
        [
          ['a', 'b'],
          ['c', 'd'],
        ],
      ),
      // ── Quoted fields ────────────────────────────────────────────────────
      (
        'quoted field containing a comma',
        '"hello, world"',
        [
          ['hello, world'],
        ],
      ),
      (
        'quoted field with escaped double-quotes',
        '"say ""hi"""',
        [
          ['say "hi"'],
        ],
      ),
      // """" = quoted field containing one "
      (
        'quoted field that is a single double-quote character',
        '""""',
        [
          ['"'],
        ],
      ),
      (
        'quoted field containing a newline',
        '"line1\nline2"',
        [
          ['line1\nline2'],
        ],
      ),
      (
        'empty quoted field "" is an empty string',
        'a,"",b',
        [
          ['a', '', 'b'],
        ],
      ),
      (
        'mix of quoted and unquoted fields on the same row',
        'plain,"has,comma",also plain',
        [
          ['plain', 'has,comma', 'also plain'],
        ],
      ),
      // ── Whitespace handling ──────────────────────────────────────────────
      // RFC-4180 does not strip whitespace from unquoted fields.
      (
        'leading and trailing whitespace in an unquoted field is preserved',
        '  hello  ',
        [
          ['  hello  '],
        ],
      ),
      (
        'field that is only whitespace is preserved',
        '   ',
        [
          ['   '],
        ],
      ),
      // ── Value types (no coercion) ────────────────────────────────────────
      (
        'numeric strings are stored as strings — no implicit type coercion',
        '42,3.14,-7',
        [
          ['42', '3.14', '-7'],
        ],
      ),
      (
        'boolean-looking values are stored as strings',
        'true,false,TRUE,FALSE',
        [
          ['true', 'false', 'TRUE', 'FALSE'],
        ],
      ),
      // ── Edge cases ───────────────────────────────────────────────────────
      // The parser treats empty/whitespace-only lines as no-ops.
      (
        'blank line in the middle of input is skipped',
        'a,b\n\nc,d',
        [
          ['a', 'b'],
          ['c', 'd'],
        ],
      ),
      (
        'all-empty cells in a row',
        ',,',
        [
          ['', '', ''],
        ],
      ),
      (
        'header row followed by data rows',
        'Name,Value\nAlice,100\nBob,"hello, world"',
        [
          ['Name', 'Value'],
          ['Alice', '100'],
          ['Bob', 'hello, world'],
        ],
      ),
    ]) {
      test(label, () {
        final c = sheetOf([
          [''],
        ]);
        addTearDown(c.dispose);
        c.loadFromCsv(csv);
        expect(_grid(c), grid);
      });
    }

    // ── Round-trip ─────────────────────────────────────────────────────────
    // Export → import → export again: the CSV is stable and every cell value
    // survives.
    for (final (label, rows) in const [
      (
        'plain values',
        [
          ['a', 'b', 'c'],
          ['d', 'e', 'f'],
        ],
      ),
      (
        'values with commas',
        [
          ['hello, world', 'foo,bar'],
        ],
      ),
      (
        'values with double-quotes',
        [
          [r'say "hi"', r'"quoted"'],
        ],
      ),
      (
        'values with newlines',
        [
          ['line1\nline2', 'plain'],
        ],
      ),
      (
        'empty cells',
        [
          ['', 'a', ''],
          ['b', '', 'c'],
        ],
      ),
      (
        'all-empty cells',
        [
          ['', '', ''],
          ['', '', ''],
        ],
      ),
      (
        'numeric strings',
        [
          ['1', '2.5', '-3'],
        ],
      ),
      (
        'whitespace-only values',
        [
          ['  ', '\t'],
        ],
      ),
    ]) {
      test('round-trip: $label', () {
        final c = sheetOf(rows);
        addTearDown(c.dispose);

        final csv1 = c.exportCsv();
        c.loadFromCsv(csv1);

        expect(c.exportCsv(), csv1, reason: 'round-trip should be stable');
        expect(_grid(c), rows);
      });
    }
  });
}
