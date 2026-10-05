import 'dart:ui' show SemanticsAction, Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/semantics.dart' show SemanticsNode;
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
  QuarkThemeColor themeColor = QuarkThemeColor.classic,
  bool scaffold = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: QuarkTheme.from(themeColor.tokensFor(brightness), brightness),
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

/// The text scale WCAG 1.4.4 asks every widget to survive (#2606).
const double largeTextScale = 2.0;

/// Runs [body] at [largeTextScale] against both [narrowViewport] and
/// [wideViewport].
///
/// The scale goes through the platform dispatcher, the way a phone's font
/// size setting does, so [pumpAt]'s `MaterialApp` picks it up without the
/// test wrapping anything in a `MediaQuery`.
void testLargeText(
  String description,
  Future<void> Function(WidgetTester tester, Size size) body,
) {
  for (final size in [narrowViewport, wideViewport]) {
    final label = size == narrowViewport ? 'narrow' : 'wide';
    testWidgets('$description at 200% text ($label)', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = largeTextScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await body(tester, size);
    });
  }
}

/// Expects no text on screen to be cut short by a box too small for it.
///
/// A fixed-height parent does not throw an overflow when its text grows: the
/// paragraph is squeezed to the parent's height and paints its lower half
/// over, or under, whatever is beside it. So this compares each paragraph's
/// laid-out height with the height its lines need at its width. Text that
/// gives up a line to an ellipsis is fine; text whose one line is taller than
/// its box is not.
void expectNoClippedText(WidgetTester tester) {
  for (final paragraph
      in tester.allRenderObjects.whereType<RenderParagraph>()) {
    final needed = paragraph.getMaxIntrinsicHeight(paragraph.size.width);
    expect(
      paragraph.size.height,
      greaterThanOrEqualTo(needed - 0.5),
      reason: '"${paragraph.text.toPlainText()}" needs $needed tall',
    );
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

/// Expects everything on screen to meet the accessibility guidelines every
/// widget in this package is held to (#2603, #2605): every tappable node is at
/// least 48x48 ([androidTapTargetGuideline]), has a label a screen reader can
/// read ([labeledTapTargetGuideline]), and every button can be pressed by one
/// ([buttonTapActionGuideline]).
///
/// Call it after [pumpAt], at both viewports: a target that grows into its
/// 48dp at one width can still be squeezed below it at the other. The size
/// check skips a target touching the edge of the screen or of a scrollable, so
/// pump the widget inset from both — a [Center] or a [Padding] is enough.
///
/// [checkSize] false skips the 48x48 check, for a widget that draws its
/// targets to a scale of its own and says why where it is called.
Future<void> expectTapTargetGuidelines(
  WidgetTester tester, {
  bool checkSize = true,
}) async {
  final handle = tester.ensureSemantics();
  await tester.pump();
  if (checkSize) {
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  }
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(buttonTapActionGuideline));
  handle.dispose();
}

/// Fails on a node a screen reader announces as an enabled button but cannot
/// press, because it has no tap action.
///
/// `Semantics(button: true, excludeSemantics: true)` around an `InkWell` does
/// exactly that: excluding the child's semantics drops its tap action along
/// with its label, so the button reads correctly and does nothing. Neither
/// stock guideline sees it, since both skip a node with no actions.
const AccessibilityGuideline buttonTapActionGuideline =
    ButtonTapActionGuideline();

/// The guideline behind [buttonTapActionGuideline].
class ButtonTapActionGuideline extends AccessibilityGuideline {
  /// Creates the guideline.
  const ButtonTapActionGuideline();

  @override
  String get description => 'Every enabled button has a tap action';

  @override
  Evaluation evaluate(WidgetTester tester) {
    var result = const Evaluation.pass();
    for (final view in tester.binding.renderViews) {
      result += _traverse(view.owner!.semanticsOwner!.rootSemanticsNode!);
    }
    return result;
  }

  Evaluation _traverse(SemanticsNode node) {
    var result = const Evaluation.pass();
    node.visitChildren((child) {
      result += _traverse(child);
      return true;
    });
    if (node.isMergedIntoParent) return result;
    final data = node.getSemanticsData();
    final flags = data.flagsCollection;
    if (flags.isButton &&
        flags.isEnabled != Tristate.isFalse &&
        !flags.isHidden &&
        !data.hasAction(SemanticsAction.tap)) {
      result += Evaluation.fail(
        '$node: announced as a button but has no tap action, so a screen '
        'reader cannot press it.',
      );
    }
    return result;
  }
}
