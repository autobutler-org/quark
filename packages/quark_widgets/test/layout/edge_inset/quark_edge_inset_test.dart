// The edge inset around chrome pinned to the bottom of the screen (#2788).
//
// A screenshot shows nothing wrong when a rounded display corner eats the
// chat composer, and MediaQuery reports no inset for the curve. So these
// tests assert the geometry instead: the system insets are cleared, the
// token gutter is there when they are zero, the keyboard does not inset the
// child twice, and an iPhone-sized corner curve misses the child's corner.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/pump.dart';

const _child = ValueKey('edge_inset_child');

/// Pumps a full-width bar pinned to the bottom of the screen at [size].
Future<double> _pumpPinnedBar(WidgetTester tester, Size size) async {
  await pumpAt(
    tester,
    const Column(
      children: [
        Expanded(child: SizedBox.shrink()),
        QuarkEdgeInset(
          child: SizedBox(key: _child, height: 40, width: double.infinity),
        ),
      ],
    ),
    size: size,
  );
  return QuarkTokens.of(tester.element(find.byKey(_child))).spacingSm;
}

/// Sets the insets a device reports, in logical pixels ([pumpAt] uses a
/// device pixel ratio of 1).
void _setInsets(
  WidgetTester tester, {
  FakeViewPadding viewPadding = FakeViewPadding.zero,
  FakeViewPadding padding = FakeViewPadding.zero,
  FakeViewPadding viewInsets = FakeViewPadding.zero,
}) {
  tester.view.viewPadding = viewPadding;
  tester.view.padding = padding;
  tester.view.viewInsets = viewInsets;
}

void main() {
  testBothViewports('keeps a token gutter off the screen edges', (
    tester,
    size,
  ) async {
    final gutter = await _pumpPinnedBar(tester, size);
    final rect = tester.getRect(find.byKey(_child));

    expect(gutter, greaterThan(0));
    expect(rect.left, gutter);
    expect(rect.right, size.width - gutter);
    expect(rect.bottom, size.height - gutter);
  });

  testBothViewports('clears the home indicator', (tester, size) async {
    const home = FakeViewPadding(bottom: 34);
    _setInsets(tester, viewPadding: home, padding: home);
    final gutter = await _pumpPinnedBar(tester, size);
    final rect = tester.getRect(find.byKey(_child));

    expect(rect.bottom, size.height - 34);
    expect(rect.left, gutter);
    expect(rect.right, size.width - gutter);
  });

  testBothViewports('clears a notch on either side in landscape', (
    tester,
    size,
  ) async {
    const notch = FakeViewPadding(left: 47, right: 47, bottom: 21);
    _setInsets(tester, viewPadding: notch, padding: notch);
    await _pumpPinnedBar(tester, size);
    final rect = tester.getRect(find.byKey(_child));

    expect(rect.left, 47);
    expect(rect.right, size.width - 47);
    expect(rect.bottom, size.height - 21);
  });

  testBothViewports('rides the keyboard without insetting twice', (
    tester,
    size,
  ) async {
    // With the keyboard up a phone still reports the home indicator in
    // viewPadding, but not in padding: the keyboard already covers it.
    const keyboard = 260.0;
    _setInsets(
      tester,
      viewPadding: const FakeViewPadding(bottom: 34),
      viewInsets: const FakeViewPadding(bottom: keyboard),
    );
    final gutter = await _pumpPinnedBar(tester, size);
    final rect = tester.getRect(find.byKey(_child));

    expect(rect.bottom, size.height - keyboard - gutter);
  });

  testWidgets('keeps an iPhone display corner off the bar', (tester) async {
    // An iPhone in portrait: rounded display corners, and a home indicator
    // inset that MediaQuery does report. The curve itself it does not.
    const size = Size(393, 852);
    const cornerRadius = 55.0;
    const home = FakeViewPadding(bottom: 34);
    _setInsets(tester, viewPadding: home, padding: home);
    await _pumpPinnedBar(tester, size);
    final rect = tester.getRect(find.byKey(_child));

    bool insidePanel(Offset point, Offset cornerCenter) =>
        point.dx >= cornerCenter.dx ||
        point.dy <= cornerCenter.dy ||
        (point - cornerCenter).distance <= cornerRadius;

    expect(
      insidePanel(
        rect.bottomLeft,
        Offset(cornerRadius, size.height - cornerRadius),
      ),
      isTrue,
      reason: 'the bottom-left corner curve cuts into the bar',
    );
    expect(
      insidePanel(
        Offset(size.width - rect.bottomRight.dx, rect.bottomRight.dy),
        Offset(cornerRadius, size.height - cornerRadius),
      ),
      isTrue,
      reason: 'the bottom-right corner curve cuts into the bar',
    );
    // Without the gutter the same bar is clipped, which is the bug.
    final flush = Offset(0, rect.bottom);
    expect(
      (flush - Offset(cornerRadius, size.height - cornerRadius)).distance,
      greaterThan(cornerRadius),
    );
  });

  testWidgets('leaves the top edge alone', (tester) async {
    const statusBar = FakeViewPadding(top: 47);
    _setInsets(tester, viewPadding: statusBar, padding: statusBar);
    await pumpAt(
      tester,
      const Align(
        alignment: Alignment.topCenter,
        child: QuarkEdgeInset(
          child: SizedBox(key: _child, height: 40, width: double.infinity),
        ),
      ),
      size: narrowViewport,
      scaffold: false,
    );

    expect(tester.getRect(find.byKey(_child)).top, 0);
  });
}
