import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The narrow viewport every widget has to survive: a small phone in portrait.
const Size narrowViewport = Size(360, 640);

/// The wide viewport: a desktop window.
const Size wideViewport = Size(1280, 800);

/// Expects every tappable thing on screen to answer taps across at least
/// 48x48 logical pixels: Android's guideline, and well above the 24 pixel
/// floor of WCAG 2.5.8 (#2605).
///
/// The app's copy of `expectTapTargetsMeetGuideline` in quark_widgets' test
/// support, which the app's tests cannot import.
Future<void> expectTapTargetsMeetGuideline(WidgetTester tester) async {
  final semantics = tester.ensureSemantics();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  semantics.dispose();
}

/// Sizes the test view to [size] for the rest of the test.
void setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}
