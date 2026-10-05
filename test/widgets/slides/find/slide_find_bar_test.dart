import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/widgets/slides/find/slide_find_button.dart';
import 'package:quark/widgets/slides/find/slide_find_controller.dart';
import 'package:quark/widgets/slides/find/slide_find_layout.dart';
import 'package:quark/widgets/slides/find/slide_find_provider.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../../support/tap_target_guidelines.dart' as tap;
import '../../../support/text_scale.dart';

ElementFrame frame() => ElementFrame(x: 0, y: 0, width: 400, height: 100);

/// Two slides: `a` (`cat`) and `b` (`cat cat`, with notes `cat`).
Presentation deck() => Presentation(
  slides: [
    Slide(
      id: 'a',
      elements: [
        TextBox(
          id: 'ta',
          frame: frame(),
          paragraphs: [TextParagraph.plain('cat')],
        ),
      ],
    ),
    Slide(
      id: 'b',
      notes: 'cat',
      elements: [
        TextBox(
          id: 'tb',
          frame: frame(),
          paragraphs: [TextParagraph.plain('cat cat')],
        ),
      ],
    ),
  ],
);

/// The find bar under a stand-in editor that can take focus, as the slide
/// editor's body would be.
class Host {
  Host() {
    find = SlideFindController(
      source: Listenable.merge([doc, slide]),
      document: () => doc,
      currentSlideId: () => slide.value,
      showSlide: (id) => slide.value = id,
    );
  }

  final doc = SlideDocumentNotifier(deck());
  final slide = ValueNotifier('a');
  late final SlideFindController find;

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          appBar: AppBar(
            actions: [
              ListenableBuilder(
                listenable: find,
                builder: (_, _) => SlideFindButton(
                  isOpen: find.isOpen,
                  onPressed: find.toggle,
                ),
              ),
            ],
          ),
          body: SlideFindLayout(
            controller: find,
            child: Focus(
              key: const ValueKey('editor'),
              autofocus: true,
              // What the canvas reads: the matches to highlight.
              child: Builder(
                builder: (context) {
                  final find = SlideFindProvider.maybeOf(context);
                  return Text(
                    'highlights ${find?.highlights.length} '
                    'current ${find?.current?.slideId}',
                    key: const ValueKey('canvas'),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    addTearDown(() {
      find.dispose();
      doc.dispose();
      slide.dispose();
    });
  }
}

Finder key(String name) => find.byKey(ValueKey(name));

Future<void> chord(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

String statusText(WidgetTester tester) =>
    tester.widget<Text>(key('slide_find_status')).data!;

void main() {
  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('Ctrl F opens the bar, typing counts, Enter steps ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final host = Host();
      await host.pump(tester);
      expect(key('slide_find_bar'), findsNothing);

      await chord(tester, LogicalKeyboardKey.keyF);
      expect(key('slide_find_bar'), findsOneWidget);
      expect(host.find.queryFocus.hasFocus, isTrue);

      await tester.enterText(key('slide_find_query'), 'cat');
      await tester.pump();
      expect(statusText(tester), '1 of 3');

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(statusText(tester), '2 of 3');
      expect(host.slide.value, 'b', reason: 'the canvas follows');
      expect(host.find.queryFocus.hasFocus, isTrue, reason: 'Enter keeps it');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(statusText(tester), '1 of 3');

      await tester.tap(key('slide_find_previous'));
      await tester.pump();
      expect(statusText(tester), '3 of 3', reason: 'wrapped');
      await tester.tap(key('slide_find_next'));
      await tester.pump();
      expect(statusText(tester), '1 of 3');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(key('slide_find_bar'), findsNothing);
      expect(host.find.highlights, isEmpty);
    });

    testWidgets('Ctrl H opens replace; Replace and Replace all ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final host = Host();
      await host.pump(tester);
      await chord(tester, LogicalKeyboardKey.keyH);
      expect(key('slide_find_replacement'), findsOneWidget);

      await tester.enterText(key('slide_find_query'), 'cat');
      await tester.enterText(key('slide_find_replacement'), 'dog');
      await tester.pump();
      await tester.tap(key('slide_find_replace'));
      await tester.pump();
      expect(
        (host.doc.presentation.slides.first.elements.single as TextBox)
            .plainText,
        'dog',
      );
      expect(statusText(tester), '1 of 2');

      await tester.tap(key('slide_find_replace_all'));
      await tester.pump();
      expect(statusText(tester), 'No results');
      expect(
        tester.widget<QuarkBarChip>(key('slide_find_replace_all')).onPressed,
        isNull,
      );
      host.doc.controller.undo();
      await tester.pump();
      expect(statusText(tester), '1 of 2', reason: 'replace all undoes whole');
    });

    testWidgets('options are labeled chips ($name)', (tester) async {
      tap.setViewport(tester, size);
      final host = Host();
      await host.pump(tester);
      await tester.tap(key('slide_find_open'));
      await tester.pump();
      if (size == tap.narrowViewport) {
        expect(key('slide_find_case'), findsNothing, reason: 'compact');
        await tester.tap(key('slide_find_toggle_options'));
        await tester.pump();
      }
      await tester.enterText(key('slide_find_query'), 'cat');
      await tester.tap(key('slide_find_notes'));
      await tester.pump();
      expect(statusText(tester), '1 of 4');
      await tester.tap(key('slide_find_this_slide'));
      await tester.pump();
      expect(statusText(tester), '1 of 1');
      await tester.tap(key('slide_find_regex'));
      await tester.enterText(key('slide_find_query'), '(');
      await tester.pump();
      expect(statusText(tester), 'Invalid pattern');
      expect(find.text('Match case'), findsOneWidget);
      expect(find.text('Whole word'), findsOneWidget);

      await tester.tap(key('slide_find_open'));
      await tester.pump();
      expect(key('slide_find_bar'), findsNothing, reason: 'toggles closed');
    });

    testWidgets('meets tap target and label guidelines ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final host = Host();
      await host.pump(tester);
      host.find
        ..open(replace: true)
        ..toggleOptions();
      await tester.pump();
      await tester.enterText(key('slide_find_query'), 'cat');
      await tester.pump();
      await tap.expectTapTargetGuidelines(tester);
    });
  }

  testWidgets('the editor inside reads the matches and follows them', (
    tester,
  ) async {
    tap.setViewport(tester, tap.wideViewport);
    final host = Host();
    await host.pump(tester);
    expect(find.text('highlights 0 current null'), findsOneWidget);
    host.find.open();
    await tester.pump();
    await tester.enterText(key('slide_find_query'), 'cat');
    await tester.pump();
    expect(find.text('highlights 3 current a'), findsOneWidget);
    host.find.next();
    await tester.pump();
    expect(find.text('highlights 3 current b'), findsOneWidget);
    host.find.close();
    await tester.pump();
    expect(find.text('highlights 0 current null'), findsOneWidget);
  });

  testLargeText('the bar fits without overflow', (tester, size) async {
    final host = Host();
    await host.pump(tester);
    host.find
      ..open(replace: true)
      ..toggleOptions();
    await tester.pump();
    await tester.enterText(key('slide_find_query'), 'cat');
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(key('slide_find_replace_all'), findsOneWidget);
    expect(statusText(tester), '1 of 3');
    final bar = tester.getRect(key('slide_find_bar'));
    expect(bar.bottom, lessThanOrEqualTo(size.height));
    expect(bar.width, size.width);
  });

  testWidgets('the bar sits along the bottom, above the keyboard', (
    tester,
  ) async {
    tap.setViewport(tester, tap.narrowViewport);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    final host = Host();
    await host.pump(tester);
    host.find.open();
    await tester.pump();
    final bar = tester.getRect(key('slide_find_bar'));
    expect(bar.bottom, moreOrLessEquals(640 - 300, epsilon: 1));
  });
}
