import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';

import '../support/table_sample.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

Matcher throwsFormatAt(String path) => throwsA(
      isA<QslideFormatException>().having((e) => e.path, 'path', path),
    );

/// A one-slide deck holding [table], a table object.
Map<String, Object?> deckWith(Map<String, Object?> table) => {
      'schemaVersion': 4,
      'slides': [
        {
          'id': 's',
          'elements': [table],
        },
      ],
    };

Map<String, Object?> tableJson({
  List<Object?> columns = const [100, 100],
  List<Object?> rows = const [50],
  List<Object?>? cells,
}) =>
    {
      'id': 't',
      'type': 'table',
      'frame': {'x': 0, 'y': 0, 'width': 200, 'height': 50},
      'columns': columns,
      'rows': rows,
      'cells': cells ??
          [
            for (var r = 0; r < rows.length; r++)
              [for (var c = 0; c < columns.length; c++) <String, Object?>{}],
          ],
    };

void main() {
  group('golden table_sample.qslide', () {
    test('encoding the table deck matches the fixture byte for byte', () {
      expect(QslideCodec.encode(tableSamplePresentation()),
          fixture('table_sample.qslide'));
    });

    test('decoding the fixture gives the table deck', () {
      final deck = QslideCodec.decode(fixture('table_sample.qslide'));
      expect(deck, tableSamplePresentation());
      final table = deck.slides.first.elementById('tbl')! as TableElement;
      expect(table.cell(2, 0).colSpan, 2);
      expect(table.cell(1, 1).fill, const SlideColor.theme(ThemeColor.accent2));
      expect(table.cell(0, 0).paragraphs.single.runs.single.bold, isTrue);
    });

    test('a table inside a group round-trips', () {
      final deck = QslideCodec.decode(fixture('table_sample.qslide'));
      expect(deck.slides[1].findElement('inner'), isA<TableElement>());
    });
  });

  group('forward compatibility', () {
    test('fields a newer writer added to a table survive a round trip', () {
      final source = fixture('table_future_fields.qslide');
      final again = QslideCodec.encode(QslideCodec.decode(source));
      expect(jsonDecode(again), jsonDecode(source));
    });

    test('they survive an edit to the table too', () {
      final doc = SlideDocumentController(
        QslideCodec.decode(fixture('table_future_fields.qslide')),
      );
      doc.setCellText('s1', 't1', 1, 0, [TextParagraph.plain('C')]);
      doc.insertTableRow('s1', 't1', 1, after: true);
      final json = jsonDecode(QslideCodec.encode(doc.presentation)) as Map;
      final table =
          ((json['slides'] as List).single['elements'] as List).single as Map;
      expect(table['style'], 'medium-2');
      final cells = table['cells'] as List;
      final first = (cells[0] as List)[0] as Map;
      expect(first['margin'], {'left': 4});
      expect((first['borders'] as Map)['diagonal'], isNotNull);
      expect(((first['borders'] as Map)['top'] as Map)['compound'], 'double');
      expect(((cells[0] as List)[1] as Map)['gradient'], isNotNull);
    });

    test('an unknown cell anchor reads as top, as a text box anchor does', () {
      final cell = SlideTableCell.fromJson({'anchor': 'baseline'}, r'$');
      expect(cell.anchor, TextAnchor.top);
    });

    test('a schema 3 reader would refuse a table file', () {
      final json = jsonDecode(fixture('table_sample.qslide')) as Map;
      expect(json['schemaVersion'], greaterThan(3));
    });
  });

  group('reading tables', () {
    test('columns and rows are scaled to fill the frame', () {
      final deck = QslideCodec.fromJson(
        deckWith(tableJson(columns: [1, 3], rows: [2, 2])),
      );
      final table = deck.slides.single.elements.single as TableElement;
      expect(table.columnWidths, [50, 150]);
      expect(table.rowHeights, [25, 25]);
    });

    test('overlapping or oversized merges are normalized', () {
      final deck = QslideCodec.fromJson(deckWith(tableJson(cells: [
        [
          {'colSpan': 9},
          {'rowSpan': 4},
        ],
      ])));
      final table = deck.slides.single.elements.single as TableElement;
      expect(table.cell(0, 0).colSpan, 2);
      expect(table.cell(0, 1).isMerged, isFalse);
    });

    test('a missing cell grid or a ragged row is refused', () {
      expect(
        () => QslideCodec.fromJson(deckWith(tableJson(cells: []))),
        throwsFormatAt(r'$.slides[0].elements[0].cells'),
      );
      expect(
        () => QslideCodec.fromJson(deckWith(tableJson(cells: [
          [<String, Object?>{}],
        ]))),
        throwsFormatAt(r'$.slides[0].elements[0].cells[0]'),
      );
    });

    test('a size that is not a positive number is refused', () {
      expect(
        () => QslideCodec.fromJson(deckWith(tableJson(columns: [100, 0]))),
        throwsFormatAt(r'$.slides[0].elements[0].columns[1]'),
      );
      expect(
        () => QslideCodec.fromJson(deckWith(tableJson(rows: ['tall']))),
        throwsFormatAt(r'$.slides[0].elements[0].rows[0]'),
      );
    });

    test('a span that is not a positive integer is refused', () {
      expect(
        () => QslideCodec.fromJson(deckWith(tableJson(cells: [
          [
            {'rowSpan': 0},
            <String, Object?>{},
          ],
        ]))),
        throwsFormatAt(r'$.slides[0].elements[0].cells[0][0].rowSpan'),
      );
    });

    test('a table past the size caps is refused before its cells are read', () {
      final huge = tableJson(
        columns: List.filled(TableElement.maxColumns, 1),
        rows: List.filled(
            TableElement.maxCells ~/ TableElement.maxColumns + 1, 1),
        cells: const [],
      );
      expect(
        () => QslideCodec.fromJson(deckWith(huge)),
        throwsFormatAt(r'$.slides[0].elements[0]'),
      );
      expect(
        () => QslideCodec.fromJson(deckWith(tableJson(columns: []))),
        throwsFormatAt(r'$.slides[0].elements[0]'),
      );
    });
  });
}
