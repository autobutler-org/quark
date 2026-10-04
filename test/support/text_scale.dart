import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

export '../../packages/quark_widgets/test/support/pump.dart'
    show expectTapTargetGuidelines, narrowViewport, wideViewport;

/// The text scale WCAG 1.4.4 asks every screen to survive (#2606).
const double largeTextScale = 2.0;

/// The two viewports a page is held to at [largeTextScale], by name.
const largeTextViewports = {'narrow': Size(360, 640), 'wide': Size(1280, 800)};

/// Sets the test view to [size] at [largeTextScale], and puts it back when the
/// test ends.
///
/// The scale goes through the platform dispatcher, the way a phone's font
/// size setting does, so `MaterialApp` and `MaterialApp.router` pick it up
/// without the test wrapping anything in a `MediaQuery`.
void useLargeText(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  tester.platformDispatcher.textScaleFactorTestValue = largeTextScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Runs [body] at [largeTextScale] at both [largeTextViewports], with the view
/// already set up by [useLargeText].
void testLargeText(
  String description,
  Future<void> Function(WidgetTester tester, Size size) body,
) {
  for (final MapEntry(key: name, value: size) in largeTextViewports.entries) {
    testWidgets('$description at 200% text ($name)', (tester) async {
      useLargeText(tester, size);
      await body(tester, size);
    });
  }
}
