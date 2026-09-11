import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/document_editor/document_page_frame.dart';

/// A block style the page leaves null does not fall back to its `paragraph`
/// style — flutter_quill substitutes its own 16px/1.15 default in the ambient
/// theme's color, which is why a list item used to render bigger and in a
/// different color than the body text beside it (#1748).
void main() {
  Future<void> pumpFrame(
    WidgetTester tester,
    Document document, {
    bool darkPage = false,
  }) async {
    final controller = QuillController(
      document: document,
      selection: const TextSelection.collapsed(offset: 0),
    );
    final focus = FocusNode();
    final scroll = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(focus.dispose);
    addTearDown(scroll.dispose);

    await tester.pumpWidget(
      MaterialApp(
        // Deliberately not the page's own theme: the page picks its own
        // ColorScheme, so anything leaking in from here is the bug.
        theme: ThemeData(
          textTheme: const TextTheme(bodyMedium: TextStyle(fontSize: 42)),
        ),
        localizationsDelegates:
            FlutterQuillLocalizations.localizationsDelegates,
        home: Scaffold(
          body: DocumentPageFrame(
            controller: controller,
            editorFocus: focus,
            scrollController: scroll,
            darkPage: darkPage,
            isReadOnly: false,
            onTap: () {},
            onKeyPressed: (_, _) => null,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  TextStyle styleOfLine(WidgetTester tester, String text) {
    final rich = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((w) => w.text.toPlainText() == text);
    return rich.text.style!;
  }

  void expectMatchesBodyText(WidgetTester tester) {
    final body = styleOfLine(tester, 'body');
    final item = styleOfLine(tester, 'item');

    expect(item.fontSize, body.fontSize);
    expect(item.height, body.height);
    expect(item.color, body.color);
  }

  testWidgets('a bulleted list item is styled like body text', (tester) async {
    await pumpFrame(
      tester,
      Document.fromJson([
        {'insert': 'body\n'},
        {'insert': 'item'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ]),
    );

    expectMatchesBodyText(tester);
  });

  testWidgets('an ordered list item is styled like body text', (tester) async {
    await pumpFrame(
      tester,
      Document.fromJson([
        {'insert': 'body\n'},
        {'insert': 'item'},
        {
          'insert': '\n',
          'attributes': {'list': 'ordered'},
        },
      ]),
    );

    expectMatchesBodyText(tester);
  });

  // WCAG 2 contrast ratio; 4.5 is the AA floor for normal-size text.
  double contrast(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
  }

  // Code text used to be drawn in `secondary`, which Quark maps to the sidebar
  // *fill*, so it nearly vanished into the code background (#1884).
  for (final darkPage in [false, true]) {
    testWidgets('code text is readable on its background '
        '(darkPage: $darkPage)', (tester) async {
      await pumpFrame(tester, Document(), darkPage: darkPage);

      final styles = tester
          .widget<QuillEditor>(find.byType(QuillEditor))
          .config
          .customStyles!;
      final block = styles.code!;
      final inline = styles.inlineCode!;

      expect(
        contrast(block.style.color!, block.decoration!.color!),
        greaterThanOrEqualTo(4.5),
      );
      expect(
        contrast(inline.style.color!, inline.backgroundColor!),
        greaterThanOrEqualTo(4.5),
      );
    });
  }
}
