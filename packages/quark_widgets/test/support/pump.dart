import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The narrow viewport every widget has to survive: a small phone in portrait.
const Size narrowViewport = Size(360, 640);

/// The wide viewport: a desktop window.
const Size wideViewport = Size(1280, 800);

/// Pumps [child] inside Quark's theme at [size].
///
/// Both viewports go through here so a layout that only works on one of them
/// fails the same way in every test file.
Future<void> pumpAt(
  WidgetTester tester,
  Widget child, {
  Size size = wideViewport,
  Brightness brightness = Brightness.dark,
  bool scaffold = true,
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
      home: scaffold ? Scaffold(body: child) : child,
    ),
  );
  await tester.pump();
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

/// Fails when anything on screen that can be tapped or long-pressed has
/// neither a label nor a tooltip, which a screen reader would announce as an
/// unnamed button (WCAG 1.1.1, 4.1.2).
Future<void> expectLabeledTapTargets(WidgetTester tester) =>
    expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
