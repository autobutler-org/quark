import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The strict document-stream and properties parsers that keep malformed or
/// cut-off preview responses out of the widget tree.
void main() {
  test('parses every block, style, span, and summary field', () {
    final document = QuarkDocument.parse('''
{"type":"meta","version":1,"format":"docx","title":"Q3 report"}
{"type":"heading","level":1,"runs":[{"text":"Summary"}]}
{"type":"paragraph","align":"justify","runs":[{"text":"Revenue ","bold":true},{"text":"rose","italic":true,"underline":true,"strike":true,"code":true,"superscript":true,"link":"https://example.com"}]}
{"type":"listItem","ordered":true,"level":2,"marker":"3.","runs":[{"text":"Third"}]}
{"type":"table","rows":[{"cells":[{"colSpan":2,"rowSpan":3,"blocks":[{"type":"paragraph","runs":[{"text":"Wide cell","link":"relative.docx"}]}]}]}]}
{"type":"image","part":"word/media/chart.png","alt":"Chart","width":640,"height":360}
{"type":"image","external":true,"alt":"Logo"}
{"type":"omitted","what":"embedded object"}
{"type":"pageBreak"}
{"type":"end","truncated":true,"words":1234,"characters":7020,"paragraphs":88,"pages":12,"warnings":["2 objects not shown"]}
''');

    expect(document.metadata?.version, 1);
    expect(document.metadata?.format, 'docx');
    expect(document.metadata?.title, 'Q3 report');
    expect(document.blocks, hasLength(8));
    expect((document.blocks[0] as QuarkDocumentHeading).level, 1);

    final paragraph = document.blocks[1] as QuarkDocumentParagraph;
    expect(paragraph.alignment, QuarkDocumentAlignment.justify);
    expect(paragraph.runs.first.bold, isTrue);
    final linked = paragraph.runs.last;
    expect(linked.italic, isTrue);
    expect(linked.underline, isTrue);
    expect(linked.strike, isTrue);
    expect(linked.code, isTrue);
    expect(linked.superscript, isTrue);
    expect(linked.link, 'https://example.com');
    expect(linked.linkIndex, 0);

    final item = document.blocks[2] as QuarkDocumentListItem;
    expect(item.ordered, isTrue);
    expect(item.level, 2);
    expect(item.marker, '3.');

    final cell =
        (document.blocks[3] as QuarkDocumentTable).rows.single.cells.single;
    expect(cell.colSpan, 2);
    expect(cell.rowSpan, 3);
    final nested = cell.blocks.single as QuarkDocumentParagraph;
    expect(nested.runs.single.linkIndex, 1);

    final image = document.blocks[4] as QuarkDocumentImage;
    expect(image.part, 'word/media/chart.png');
    expect(image.width, 640);
    expect(image.height, 360);
    expect((document.blocks[5] as QuarkDocumentImage).external, isTrue);
    expect(
      (document.blocks[6] as QuarkDocumentOmitted).what,
      'embedded object',
    );
    expect(document.blocks[7], isA<QuarkDocumentPageBreak>());
    expect(document.summary?.truncated, isTrue);
    expect(document.summary?.pages, 12);
    expect(document.summary?.words, 1234);
    expect(document.summary?.warnings, ['2 objects not shown']);
  });

  test('requires metadata first and a summary last', () {
    expect(
      () => QuarkDocument.parse(
        '{"type":"paragraph","runs":[]}\n'
        '{"type":"end","truncated":false,"words":0,'
        '"characters":0,"paragraphs":0}',
      ),
      throwsFormatException,
    );
    expect(
      () => QuarkDocument.parse(
        '{"type":"meta","version":1,"format":"docx"}\n'
        '{"type":"paragraph","runs":[]}',
      ),
      throwsFormatException,
    );
    expect(
      () => QuarkDocument.parse(
        '{"type":"meta","version":1,"format":"docx"}\n'
        '{"type":"mystery"}\n'
        '{"type":"end","truncated":false,"words":0,'
        '"characters":0,"paragraphs":0}',
      ),
      throwsFormatException,
    );
  });

  test('rejects invalid levels, spans, alignments, and field types', () {
    Map<String, dynamic> paragraph(String align) => {
      'type': 'paragraph',
      'align': align,
      'runs': <Object>[],
    };

    expect(
      () => QuarkDocumentBlock.fromJson(paragraph('diagonal')),
      throwsFormatException,
    );
    expect(
      () => QuarkDocumentBlock.fromJson({
        'type': 'heading',
        'level': 7,
        'runs': <Object>[],
      }),
      throwsFormatException,
    );
    expect(
      () => QuarkDocumentBlock.fromJson({
        'type': 'table',
        'rows': [
          {
            'cells': [
              {'colSpan': 0, 'rowSpan': 1, 'blocks': <Object>[]},
            ],
          },
        ],
      }),
      throwsFormatException,
    );
    expect(
      () => QuarkDocumentBlock.fromJson({'type': 'image', 'width': 'wide'}),
      throwsFormatException,
    );
  });

  test('parses document properties and rejects malformed values', () {
    final properties = DocumentProperties.fromJson({
      'title': 'Q3 report',
      'author': 'Ada',
      'created': '2026-10-15T12:30:00Z',
      'pages': 12,
      'words': 1234,
      'application': 'Writer',
      'countsSource': 'saved',
    });

    expect(properties.title, 'Q3 report');
    expect(properties.created, DateTime.utc(2026, 10, 15, 12, 30));
    expect(properties.pages, 12);
    expect(properties.isEmpty, isFalse);
    expect(const DocumentProperties().isEmpty, isTrue);
    expect(
      () => DocumentProperties.fromJson({'pages': 'twelve'}),
      throwsFormatException,
    );
    expect(
      () => DocumentProperties.fromJson({'created': 'Thursday'}),
      throwsFormatException,
    );
  });
}
