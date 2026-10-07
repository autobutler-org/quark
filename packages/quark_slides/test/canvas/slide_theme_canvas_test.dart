import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_slides/src/canvas/slide_background_view.dart';

import '../support/canvas_harness.dart';

/// A title-layout slide `s` in [theme]: the title placeholder `title`
/// holding "Agenda", the subtitle `sub` left empty, and an accent-filled
/// rectangle `box`.
Presentation themedDeck(SlideTheme? theme) {
  final size = SlideSize.widescreen;
  final layout = SlideLayout.title;
  return Presentation(
    theme: theme,
    slides: [
      Slide(
        id: 's',
        layoutId: layout.id,
        elements: [
          layout.placeholder('title')!.emptyBox('title', size).copyWith(
            paragraphs: [
              TextParagraph.plain('Agenda', alignment: TextAlignment.center),
            ],
          ),
          layout.placeholder('subtitle')!.emptyBox('sub', size),
          ShapeElement(
            id: 'box',
            frame: ElementFrame(x: 100, y: 100, width: 200, height: 200),
            fill: const SlideColor.theme(ThemeColor.accent1),
          ),
        ],
      ),
    ],
  );
}

/// The color the slide's background is painted.
Color backgroundColor(WidgetTester tester) => tester
    .widget<ColoredBox>(
      find.descendant(
        of: find.byType(SlideBackgroundView),
        matching: find.byType(ColoredBox),
      ),
    )
    .color;

/// The render object painting the element [id]'s shape.
RenderObject shapeOf(WidgetTester tester, String id) => tester.renderObject(
      find.descendant(of: elementKey(id), matching: find.byType(CustomPaint)),
    );

/// The root text style of the element [id]'s first paragraph.
TextStyle textStyleOf(WidgetTester tester, String id) => tester
    .renderObject<RenderParagraph>(
      find
          .descendant(of: elementKey(id), matching: find.byType(RichText))
          .first,
    )
    .text
    .style!;

void main() {
  group('a themed deck', () {
    testBothViewports('paints role colors and text styles from its theme',
        (tester, size) async {
      final theme = SlideThemes.warm;
      await pumpCanvas(tester, SlideDocumentNotifier(themedDeck(theme)),
          size: size);
      expect(backgroundColor(tester), const Color(0xFFFFF8F0));
      expect(
        shapeOf(tester, 'box'),
        paints..path(color: const Color(0xFFC2410C)),
      );
      final title = textStyleOf(tester, 'title');
      expect(title.fontSize, theme.title.fontSize);
      expect(title.fontFamily, 'Georgia');
      expect(title.color, const Color(0xFF3B2A20));
    });

    testBothViewports('restyles in place when the theme changes',
        (tester, size) async {
      final doc = SlideDocumentNotifier(themedDeck(SlideThemes.light));
      await pumpCanvas(tester, doc, size: size);
      expect(backgroundColor(tester), const Color(0xFFFFFFFF));
      doc.controller.setTheme(SlideThemes.dark);
      await tester.pump();
      expect(backgroundColor(tester), const Color(0xFF121318));
      expect(
        shapeOf(tester, 'box'),
        paints..path(color: const Color(0xFF7AA2FF)),
      );
      expect(textStyleOf(tester, 'title').color, const Color(0xFFF3F4F6));
      doc.controller.undo();
      await tester.pump();
      expect(backgroundColor(tester), const Color(0xFFFFFFFF));
    });

    testBothViewports('keeps slide type at 2.0 text scale',
        (tester, size) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCanvas(
        tester,
        SlideDocumentNotifier(themedDeck(SlideThemes.highContrast)),
        size: size,
      );
      expect(tester.takeException(), isNull);
      expect(textStyleOf(tester, 'title').fontSize, 64);
      final paragraph = tester.renderObject<RenderParagraph>(
        find
            .descendant(
                of: elementKey('title'), matching: find.byType(RichText))
            .first,
      );
      expect(paragraph.textScaler, TextScaler.noScaling);
    });

    testBothViewports('placeholders announce their role', (tester, size) async {
      final semantics = tester.ensureSemantics();
      await pumpCanvas(
        tester,
        SlideDocumentNotifier(themedDeck(SlideThemes.cool)),
        size: size,
      );
      expect(find.bySemanticsLabel('Title: Agenda'), findsOne);
      expect(
        find.bySemanticsLabel('Subtitle placeholder: Click to add subtitle'),
        findsOne,
      );
      expect(find.bySemanticsLabel('Rectangle shape'), findsOne);
      semantics.dispose();
    });
  });

  group('a deck without a theme', () {
    testBothViewports('takes the style\'s colors and the app\'s accents',
        (tester, size) async {
      await pumpCanvas(tester, SlideDocumentNotifier(themedDeck(null)),
          size: size);
      final scheme =
          Theme.of(tester.element(find.byType(SlideCanvas))).colorScheme;
      // SlideCanvasStyle.fromTheme keeps the default white slide.
      expect(backgroundColor(tester), const Color(0xFFFFFFFF));
      expect(shapeOf(tester, 'box'), paints..path(color: scheme.primary));
      expect(textStyleOf(tester, 'title').fontSize, 60);
      expect(textStyleOf(tester, 'title').color, const Color(0xFF000000));
    });

    test('the fallback theme is built from the style and scheme', () {
      final scheme = ColorScheme.fromSeed(seedColor: Colors.teal);
      final style = SlideCanvasStyle.fromTheme(ThemeData(colorScheme: scheme))
          .copyWith(slideColor: const Color(0xFF101010), fontSize: 30);
      final theme = slideFallbackTheme(style, scheme);
      expect(theme.colors[ThemeColor.background], 0xFF101010);
      expect(theme.colors[ThemeColor.accent2], scheme.secondary.toARGB32());
      expect(theme.body.fontSize, 30);
      expect(theme.title, SlideThemes.light.title);
    });
  });

  group('read-only', () {
    testBothViewports('draws in the theme it is given', (tester, size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final deck = themedDeck(null);
      await tester.pumpWidget(
        MaterialApp(
          home: SlideCanvas.readOnly(
            slide: deck.slides.single,
            size: deck.size,
            theme: SlideThemes.dark,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(backgroundColor(tester), const Color(0xFF121318));
      expect(
        shapeOf(tester, 'box'),
        paints..path(color: const Color(0xFF7AA2FF)),
      );
    });
  });
}
