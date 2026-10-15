import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

final QuarkDocument _document = QuarkDocument.parse('''
{"type":"meta","version":1,"format":"docx","title":"Q3 report"}
{"type":"heading","level":1,"runs":[{"text":"Summary"}]}
{"type":"paragraph","align":"justify","runs":[{"text":"Revenue ","bold":true},{"text":"rose","italic":true},{"text":" again.","underline":true,"link":"https://example.com"}]}
{"type":"listItem","ordered":true,"level":0,"marker":"1.","runs":[{"text":"First point"}]}
{"type":"table","rows":[{"cells":[{"colSpan":2,"rowSpan":2,"blocks":[{"type":"paragraph","runs":[{"text":"Spanning header"}]}]},{"colSpan":1,"rowSpan":1,"blocks":[{"type":"paragraph","runs":[{"text":"Side"}]}]}]},{"cells":[{"colSpan":1,"rowSpan":1,"blocks":[{"type":"paragraph","runs":[{"text":"Below","link":"relative.docx"}]}]}]}]}
{"type":"image","part":"word/media/image1.png","alt":"Chart of revenue","width":640,"height":360}
{"type":"image","external":true,"alt":"Company logo"}
{"type":"omitted","what":"embedded object"}
{"type":"pageBreak"}
{"type":"end","truncated":true,"words":1234,"characters":7020,"paragraphs":88,"pages":12,"warnings":["1 object not shown"]}
''');

/// The document renderer's lazy layout, caller-owned links and images, every
/// block kind, loading/error/empty states, tokens, and phone-width behavior.
void main() {
  testBothViewports('renders every document block without overflowing', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkDocumentView(document: _document),
      size: Size(size.width, 3000),
    );

    expect(tester.takeException(), isNull);
    for (var index = 0; index < _document.blocks.length; index++) {
      expect(find.byKey(ValueKey('document_block_$index')), findsOneWidget);
    }
    final visibleText = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((text) => text.text.toPlainText())
        .join('\n');
    for (final text in [
      'Summary',
      'Revenue ',
      'rose',
      ' again.',
      '1.',
      'First point',
      'Spanning header',
      'Side',
      'Below',
      'Chart of revenue',
      'Company logo (external image not shown)',
      'embedded object not shown',
      'Page break',
    ]) {
      expect(visibleText, contains(text));
    }
    expect(
      find.byKey(const ValueKey('document_truncated_banner')),
      findsOneWidget,
    );
    expect(find.text('Showing the first 12 pages.'), findsOneWidget);

    final firstBlock = tester.getRect(
      find.byKey(const ValueKey('document_block_0')),
    );
    expect(
      firstBlock.width,
      lessThanOrEqualTo(QuarkDocumentView.maxContentWidth),
    );
    expect(firstBlock.center.dx, closeTo(size.width / 2, 0.5));
  });

  testBothViewports('reports links exactly once and leaves them inert', (
    tester,
    size,
  ) async {
    final links = <String>[];
    await pumpAt(
      tester,
      QuarkDocumentView(document: _document, onLinkTap: links.add),
      size: Size(size.width, 3000),
    );

    await tester.tap(find.byKey(const ValueKey('document_link_0')));
    await tester.tap(find.byKey(const ValueKey('document_link_1')));
    expect(links, ['https://example.com', 'relative.docx']);

    await pumpAt(
      tester,
      QuarkDocumentView(document: _document),
      size: Size(size.width, 3000),
    );
    await tester.tap(find.byKey(const ValueKey('document_link_0')));
    expect(tester.takeException(), isNull);
  });

  testBothViewports('hands only embedded images to the caller', (
    tester,
    size,
  ) async {
    final built = <QuarkDocumentImage>[];
    await pumpAt(
      tester,
      QuarkDocumentView(
        document: _document,
        imageBuilder: (context, image) {
          built.add(image);
          return ColoredBox(
            color: QuarkTokens.of(context).card,
            child: Text('built:${image.part}'),
          );
        },
      ),
      size: Size(size.width, 3000),
    );

    expect(tester.takeException(), isNull);
    expect(built, hasLength(1));
    expect(built.single.part, 'word/media/image1.png');
    expect(find.text('built:word/media/image1.png'), findsOneWidget);
    expect(
      find.text('Company logo (external image not shown)'),
      findsOneWidget,
    );
  });

  testBothViewports('shows a loader while loading', (tester, size) async {
    await pumpAt(
      tester,
      QuarkDocumentView(document: _document, isLoading: true),
      size: size,
    );
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testBothViewports('shows the caller error and retries', (tester, size) async {
    final events = <String>[];
    await pumpAt(
      tester,
      QuarkDocumentView(
        document: _document,
        error: "Couldn't open the document.",
        onRetry: () => events.add('retry'),
      ),
      size: size,
    );
    expect(find.text("Couldn't open the document."), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    await tester.tap(find.byKey(const ValueKey('document_view_retry')));
    expect(events, ['retry']);

    await pumpAt(
      tester,
      const QuarkDocumentView(
        document: QuarkDocument.empty(),
        error: 'Offline',
      ),
      size: size,
    );
    expect(find.byKey(const ValueKey('document_view_retry')), findsNothing);
  });

  testBothViewports('shows the empty document state', (tester, size) async {
    await pumpAt(
      tester,
      const QuarkDocumentView(document: QuarkDocument.empty()),
      size: size,
    );
    expect(find.text('Empty document'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: links and the truncated banner use tokens', (
      tester,
    ) async {
      await pumpAt(
        tester,
        QuarkDocumentView(document: _document, onLinkTap: (_) {}),
        size: const Size(800, 3000),
        brightness: brightness,
      );

      final link = tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('document_link_0')),
          matching: find.byType(Text),
        ),
      );
      expect(link.style?.color, tokens.primary);
      final banner = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('document_truncated_banner')),
      );
      expect((banner.decoration as BoxDecoration).color, tokens.card);
      expect(tester.takeException(), isNull);
    });
  }

  testBothViewports('keeps a long lazy document responsive', (
    tester,
    size,
  ) async {
    final lines = <String>[
      '{"type":"meta","version":1,"format":"rtf"}',
      for (var index = 0; index < 200; index++)
        '{"type":"paragraph","runs":[{"text":"${'Long text ' * 20}$index"}]}',
      '{"type":"end","truncated":false,"words":4000,'
          '"characters":20000,"paragraphs":200}',
    ];
    await pumpAt(
      tester,
      QuarkDocumentView(document: QuarkDocument.fromLines(lines)),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('document_block_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('document_block_199')), findsNothing);
  });
}
