import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

const String _longUrl =
    'https://example.com/a/very/long/path/that/keeps/going/and/going/and/'
    'going/without/a/single/space/to/break/on/until/it/is/far/wider/than/a/'
    'phone';

final String _source =
    '''
# Title

A paragraph with **bold**, *italic*, ~~gone~~, `inline()` and a
[link](https://example.com/one "t").

###### Small heading

- Apple
- Pear
  - Nested pear

3. Third
4. Fourth

- [x] Done task
- [ ] Open task

> Quoted words

```dart
final answer = 42; // ${'long ' * 80}
```

    indented code

---

| Name | Centered | Amount | Notes |
| :--- | :------: | -----: | ----- |
| Alpha | mid | 12 | ${'wide cell ' * 20} |
| Beta | mid | 7 | short |

$_longUrl

<script>alert(1)</script>

Inline <b>tag</b> and ![A cat](cat.png) and [second](relative/path.md).

> [!NOTE]
> Alert body
''';

/// All the text on screen, widget spans included.
String _allText(WidgetTester tester) => tester
    .widgetList<RichText>(find.byType(RichText))
    .map((text) => text.text.toPlainText())
    .join('\n');

/// The runs of text in the paragraph reading exactly [text], in order.
List<TextSpan> _runs(WidgetTester tester, String text) {
  final runs = <TextSpan>[];
  tester
      .widget<RichText>(
        find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == text,
        ),
      )
      .text
      .visitChildren((span) {
        if (span is TextSpan && span.text != null) runs.add(span);
        return true;
      });
  return runs;
}

/// Scrolls the document until [finder] is built and on screen.
Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pump();
}

void main() {
  final document = QuarkMarkdownDocument.parse(_source);

  group('QuarkMarkdownDocument', () {
    test('empty and blank sources are empty', () {
      expect(const QuarkMarkdownDocument.empty().isEmpty, isTrue);
      expect(QuarkMarkdownDocument.parse('').isEmpty, isTrue);
      expect(QuarkMarkdownDocument.parse(' \n\n').isEmpty, isTrue);
      expect(document.isEmpty, isFalse);
    });
  });

  testBothViewports('renders the whole document without overflowing', (
    tester,
    size,
  ) async {
    // Tall enough to build every block, so one that overflows its width
    // throws.
    await pumpAt(
      tester,
      QuarkMarkdownView(document: document),
      size: Size(size.width, 6000),
    );
    expect(tester.takeException(), isNull);

    final text = _allText(tester);
    for (final expected in [
      'Title',
      'Small heading',
      'bold',
      'inline()',
      'Apple',
      'Nested pear',
      '3.',
      '4.',
      'Done task',
      'Quoted words',
      'final answer = 42;',
      'indented code',
      'Alpha',
      'Centered',
      _longUrl,
      'Alert body',
    ]) {
      expect(text, contains(expected));
    }
    // A numbered list honors its start.
    expect(text, isNot(contains('1.')));

    expect(find.byKey(const ValueKey('markdown_task_0')), findsOneWidget);
    expect(
      tester.widget<Icon>(find.byKey(const ValueKey('markdown_task_0'))).icon,
      QuarkIcons.check_circle_rounded,
    );
    expect(
      tester.widget<Icon>(find.byKey(const ValueKey('markdown_task_1'))).icon,
      QuarkIcons.radio_button_unchecked,
    );
    expect(find.byType(Checkbox), findsNothing);
    expect(find.byType(Divider), findsOneWidget);

    // The header row is bold and the columns keep their alignment.
    final table = find.byType(Table);
    expect(table, findsOneWidget);
    RichText cell(String text) => tester.widget<RichText>(
      find.descendant(
        of: table,
        matching: find.byWidgetPredicate(
          (widget) => widget is RichText && widget.text.toPlainText() == text,
        ),
      ),
    );
    expect(cell('Centered').textAlign, TextAlign.center);
    expect(cell('12').textAlign, TextAlign.right);
    expect(cell('Alpha').textAlign, TextAlign.left);
    expect(_runs(tester, 'Name').single.style!.fontWeight, FontWeight.bold);
    expect(
      _runs(tester, 'Alpha').single.style!.fontWeight,
      isNot(FontWeight.bold),
    );

    // The column stops widening and stays centered.
    final title = tester.getRect(find.text('Title', findRichText: true));
    expect(title.width, lessThanOrEqualTo(QuarkMarkdownView.maxContentWidth));
    expect(title.center.dx, closeTo(size.width / 2, 0.5));
  });

  testBothViewports('scrolls to the end at the real viewport', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkMarkdownView(document: document), size: size);
    expect(tester.takeException(), isNull);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(find.textContaining('Alert body', findRichText: true), findsNothing);
    await _reveal(
      tester,
      find.textContaining('Alert body', findRichText: true),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('highlights a fence that names its language', (tester) async {
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: QuarkMarkdownDocument.parse(
          '```dart\nfinal x = 1;\n```\n\n```\nfinal y = 2;\n```',
        ),
      ),
    );
    final keyword = _runs(tester, 'final x = 1;').first;
    expect(keyword.text, 'final');
    expect(
      keyword.style!.color,
      QuarkTokens.of(tester.element(find.byType(QuarkMarkdownView))).primary,
    );
    expect(_runs(tester, 'final y = 2;'), hasLength(1));
  });

  testWidgets('shows raw HTML as text', (tester) async {
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: QuarkMarkdownDocument.parse(
          '<script>alert(1)</script>\n\n'
          'Inline <b>tag</b> and <img src="x.png" onerror="alert(2)">.\n\n'
          '<a href="javascript:alert(3)">click</a>',
        ),
        onLinkTap: (_) => fail('raw HTML is not a link'),
        imageBuilder: (_, _, _) => fail('raw HTML is not an image'),
      ),
    );
    final text = _allText(tester);
    expect(text, contains('<script>alert(1)</script>'));
    expect(text, contains('Inline <b>tag</b> and <img src="x.png"'));
    expect(text, contains('<a href="javascript:alert(3)">click</a>'));
    expect(find.byKey(const ValueKey('markdown_link_0')), findsNothing);
    expect(find.byKey(const ValueKey('markdown_image_0')), findsNothing);
  });

  testWidgets('reports the raw href of a tapped link', (tester) async {
    final taps = <String>[];
    await pumpAt(
      tester,
      QuarkMarkdownView(document: document, onLinkTap: taps.add),
    );
    await tester.tap(find.byKey(const ValueKey('markdown_link_0')));
    expect(taps, ['https://example.com/one']);

    // The bare URL is an autolink; the relative link comes after it.
    await _reveal(tester, find.byKey(const ValueKey('markdown_link_2')));
    await tester.tap(find.byKey(const ValueKey('markdown_link_2')));
    expect(taps.last, 'relative/path.md');
  });

  testBothViewports('leaves links inert without onLinkTap', (
    tester,
    size,
  ) async {
    await pumpAt(tester, QuarkMarkdownView(document: document), size: size);
    final link = find.byKey(const ValueKey('markdown_link_0'));
    expect(link, findsOneWidget);
    expect(
      find.descendant(of: link, matching: find.byType(GestureDetector)),
      findsNothing,
    );
    await tester.tap(link);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('hands images to imageBuilder with src and alt', (
    tester,
    size,
  ) async {
    final built = <(String, String)>[];
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: QuarkMarkdownDocument.parse(
          '![A cat](cat.png)\n\n| Pic |\n| --- |\n| ![Dog](../dog.jpg) |',
        ),
        imageBuilder: (context, src, alt) {
          built.add((src, alt));
          // A LayoutBuilder has no intrinsic size: the table has to cope.
          return LayoutBuilder(
            builder: (context, constraints) =>
                SizedBox(width: 40, height: 40, child: Text('img:$src')),
          );
        },
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expect(built.toSet(), {('cat.png', 'A cat'), ('../dog.jpg', 'Dog')});
    expect(find.byKey(const ValueKey('markdown_image_0')), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown_image_1')), findsOneWidget);
    expect(find.text('img:cat.png'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the alt text when no imageBuilder is given', (
    tester,
  ) async {
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: QuarkMarkdownDocument.parse('![A cat](cat.png)'),
      ),
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('markdown_image_0')),
        matching: find.text('A cat'),
      ),
      findsOneWidget,
    );
    expect(find.byType(Image), findsNothing);
  });

  testBothViewports('renders GitHub alerts as callouts', (tester, size) async {
    const kinds = {
      'NOTE': ('Note', QuarkIcons.info_outline),
      'TIP': ('Tip', QuarkIcons.light_mode_outlined),
      'IMPORTANT': ('Important', QuarkIcons.star_border),
      'WARNING': ('Warning', QuarkIcons.warning_amber),
      'CAUTION': ('Caution', QuarkIcons.error_outline),
    };
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: QuarkMarkdownDocument.parse(
          kinds.keys
              .map((kind) => '> [!$kind]\n> Body of $kind ${'word ' * 30}')
              .join('\n\n'),
        ),
      ),
      size: size,
    );
    expect(tester.takeException(), isNull);
    final quark = QuarkTokens.of(
      tester.element(find.byType(QuarkMarkdownView)),
    );
    final colors = [
      quark.primary,
      quark.success,
      quark.primary,
      quark.warning,
      quark.error,
    ];
    var index = 0;
    for (final MapEntry(key: kind, value: (title, icon)) in kinds.entries) {
      final alert = find.byKey(ValueKey('markdown_alert_$index'));
      await _reveal(tester, alert);
      expect(alert, findsOneWidget);
      Finder inAlert(Finder finder) =>
          find.descendant(of: alert, matching: finder);
      expect(inAlert(find.text(title, findRichText: true)), findsOneWidget);
      expect(
        inAlert(find.textContaining('Body of $kind', findRichText: true)),
        findsOneWidget,
      );
      expect(tester.widget<Icon>(inAlert(find.byType(Icon))).icon, icon);
      expect(
        tester.widget<Icon>(inAlert(find.byType(Icon))).color,
        colors[index],
      );
      index++;
    }
  });

  testWidgets('keeps a plain quote a quote', (tester) async {
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: QuarkMarkdownDocument.parse('> [!NOPE]\n> Just a quote'),
      ),
    );
    expect(find.byKey(const ValueKey('markdown_alert_0')), findsNothing);
    expect(find.textContaining('[!NOPE]', findRichText: true), findsOneWidget);
  });

  testWidgets('shows a loader while loading', (tester) async {
    await pumpAt(
      tester,
      QuarkMarkdownView(document: document, isLoading: true),
    );
    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('shows the error and retries', (tester) async {
    var retries = 0;
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: document,
        error: "Couldn't load the file.",
        onRetry: () => retries++,
      ),
    );
    expect(find.text("Couldn't load the file."), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
    await tester.tap(find.byKey(const ValueKey('markdown_view_retry')));
    expect(retries, 1);

    await pumpAt(
      tester,
      const QuarkMarkdownView(
        document: QuarkMarkdownDocument.empty(),
        error: 'Nope',
      ),
    );
    expect(find.text('Nope'), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown_view_retry')), findsNothing);
  });

  testWidgets('shows Empty file for an empty document', (tester) async {
    await pumpAt(
      tester,
      const QuarkMarkdownView(document: QuarkMarkdownDocument.empty()),
    );
    expect(find.text('Empty file'), findsOneWidget);
    expect(find.byKey(const ValueKey('markdown_view_status')), findsNothing);
  });

  testBothViewports('shows the status label above the content', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      QuarkMarkdownView(
        document: document,
        statusLabel: 'Showing the first 1 MB of 5 MB',
      ),
      size: size,
    );
    final status = find.byKey(const ValueKey('markdown_view_status'));
    expect(tester.widget<Text>(status).data, 'Showing the first 1 MB of 5 MB');
    expect(
      tester.getBottomLeft(status).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.byType(ListView)).dy),
    );
  });

  testLargeText('survives large text', (tester, size) async {
    await pumpAt(
      tester,
      QuarkMarkdownView(document: document, statusLabel: 'Partial'),
      size: Size(size.width, 9000),
    );
    expect(tester.takeException(), isNull);
  });
}
