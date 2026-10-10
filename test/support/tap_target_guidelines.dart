import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

/// A small phone in portrait, the narrow case every touch target has to
/// survive.
const Size narrowViewport = Size(360, 640);

/// A desktop window, the wide case.
const Size wideViewport = Size(1280, 800);

/// Sizes the test view to [size] at a device pixel ratio of 1, and resets it
/// when the test ends.
void setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Expects every tappable node on screen to be at least 48x48
/// ([androidTapTargetGuideline]) and to carry a label a screen reader can
/// read ([labeledTapTargetGuideline]) — the app-side half of #2603 and #2605,
/// held to the same guidelines as `packages/quark_widgets`.
///
/// The size check skips a target touching the edge of the screen or of a
/// scrollable, so pump the widget inset from both.
Future<void> expectTapTargetGuidelines(WidgetTester tester) async {
  final handle = tester.ensureSemantics();
  await tester.pump();
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  handle.dispose();
}
