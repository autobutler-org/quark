import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The narrow viewport every widget has to survive: a small phone in portrait.
const Size narrowViewport = Size(360, 640);

/// The wide viewport: a desktop window.
const Size wideViewport = Size(1280, 800);

/// Pumps [child] inside Quark's theme at [size], with text scaled by
/// [textScaler].
///
/// Both viewports go through here so a layout that only works on one of them
/// fails the same way in every test file.
Future<void> pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = wideViewport,
  Brightness brightness = Brightness.dark,
  bool scaffold = true,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.from(
        brightness == Brightness.dark ? QuarkTokens.dark : QuarkTokens.light,
        brightness,
      ),
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: textScaler),
        child: app!,
      ),
      home: scaffold ? Scaffold(body: child) : child,
    ),
  );
  await tester.pump();
}

/// The text size WCAG 1.4.4 asks a layout to survive: 200% (#2606).
const TextScaler largeText = TextScaler.linear(2);

/// Pumps [child] at [narrowViewport] with [largeText], the hardest case for
/// a fixed-height box with a label in it, and expects nothing to overflow and
/// no text to be cut off top or bottom.
///
/// A label squeezed into a box shorter than its line throws nothing: it is
/// just clipped. So every paragraph on screen is also checked for being laid
/// out at least as tall as its text needs.
Future<void> expectSurvivesLargeText(
  WidgetTester tester,
  Widget child, {
  bool scaffold = true,
}) async {
  await pumpAt(
    tester,
    child,
    size: narrowViewport,
    scaffold: scaffold,
    textScaler: largeText,
  );
  expect(tester.takeException(), isNull);
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(
        paragraph.getMaxIntrinsicHeight(paragraph.size.width) - 0.5,
      ),
      reason: '"${paragraph.text.toPlainText()}" is cut off',
    );
  }
}

/// Runs [body] against both [narrowViewport] and [wideViewport].
///
/// Every widget in this package ships with a narrow and a wide case (#1599),
/// and this is the shortest way to write both.
void testBothViewports(
  String description,
  Future<void> Function(WidgetTester tester, Size size) body,
) {
  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    testWidgets('$description ($label)', (tester) => body(tester, size));
  }
}

/// The size [button] is drawn at: its first [Material], which is the filled,
/// bordered shape inside whatever transparent tap target surrounds it.
Size drawnSize(WidgetTester tester, Finder button) => tester.getSize(
  find.descendant(of: button, matching: find.byType(Material)).first,
);

/// Expects every tappable thing on screen to answer taps across at least
/// 48x48 logical pixels: Android's guideline, and well above the 24 pixel
/// floor of WCAG 2.5.8 (#2605).
Future<void> expectTapTargetsMeetGuideline(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  semantics.dispose();
}

/// Pumps the sheet body [body] inside a [QuarkSheet] at [size], the frame
/// every sheet body is shown in, so a body taller than the viewport scrolls
/// the way it does in the app.
Future<void> pumpInSheet(
  WidgetTester tester,
  Widget body, {
  Size size = wideViewport,
  Brightness brightness = Brightness.dark,
}) => pumpAt(
  tester,
  Align(
    alignment: Alignment.bottomCenter,
    child: QuarkSheet(title: 'Sheet', onClose: () {}, child: body),
  ),
  size: size,
  brightness: brightness,
);
