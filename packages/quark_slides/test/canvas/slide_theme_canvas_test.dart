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
    testBothViewports('draws in the light theme under any app theme',
        (tester, size) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final document = SlideDocumentNotifier(themedDeck(null));
      final light = SlideThemes.light;
      for (final app in [
        ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal)),
        ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.pink,
            brightness: Brightness.dark,
          ),
        ),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: app,
            home: Scaffold(body: SlideCanvas(document: document, slideId: 's')),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          backgroundColor(tester),
          Color(light.colors[ThemeColor.background]),
        );
        expect(
          shapeOf(tester, 'box'),
          paints..path(color: Color(light.colors[ThemeColor.accent1])),
        );
        expect(textStyleOf(tester, 'title').fontSize, light.title.fontSize);
        expect(
          textStyleOf(tester, 'title').color,
          Color(light.colors[ThemeColor.text]),
        );
      }
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
