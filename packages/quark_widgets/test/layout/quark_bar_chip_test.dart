import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  const key = ValueKey('upload');

  Widget chip({
    VoidCallback? onPressed,
    bool active = false,
    String? tooltip,
    bool keepLabel = false,
  }) => Center(
    child: QuarkBarChip(
      key: key,
      icon: QuarkIcons.upload_rounded,
      label: 'Upload',
      onPressed: onPressed,
      active: active,
      tooltip: tooltip,
      keepLabel: keepLabel,
    ),
  );

  testBothViewports('runs its action', (tester, size) async {
    var presses = 0;
    await pumpAt(tester, chip(onPressed: () => presses++), size: size);

    expect(find.byIcon(QuarkIcons.upload_rounded), findsOneWidget);
    await tester.tap(find.byKey(key));
    await tester.pump();

    expect(presses, 1);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('stands as tall as a bar icon button', (
    tester,
    size,
  ) async {
    await pumpAt(tester, chip(onPressed: () {}), size: size);

    expect(tester.getSize(find.byKey(key)).height, QuarkBarIconButton.size);
  });

  testWidgets('wide: shows its label', (tester) async {
    await pumpAt(tester, chip(onPressed: () {}), size: wideViewport);

    expect(find.text('Upload'), findsOneWidget);
    expect(find.byType(Tooltip), findsNothing);
  });

  testWidgets('narrow: gives its label up to the tooltip', (tester) async {
    await pumpAt(tester, chip(onPressed: () {}), size: narrowViewport);

    expect(find.text('Upload'), findsNothing);
    expect(find.byTooltip('Upload'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(key)),
      const Size.square(QuarkBarIconButton.size),
    );
  });

  testWidgets('narrow: keeps its label when asked to', (tester) async {
    await pumpAt(
      tester,
      chip(onPressed: () {}, keepLabel: true),
      size: narrowViewport,
    );

    expect(find.text('Upload'), findsOneWidget);
  });

  testWidgets('tints itself with the primary token while active', (
    tester,
  ) async {
    await pumpAt(
      tester,
      chip(onPressed: () {}, active: true),
      brightness: Brightness.light,
    );

    final label = tester.widget<RichText>(
      find.descendant(of: find.text('Upload'), matching: find.byType(RichText)),
    );
    expect(label.text.style!.color, QuarkTokens.light.primary);
  });

  testWidgets('explains a mode label with its tooltip', (tester) async {
    await pumpAt(
      tester,
      chip(onPressed: () {}, tooltip: 'Add files from this device'),
      size: wideViewport,
    );
    expect(find.byTooltip('Add files from this device'), findsOneWidget);
  });

  testWidgets('is disabled without a callback', (tester) async {
    await pumpAt(tester, chip(), size: wideViewport);

    expect(
      tester.widget<ButtonStyleButton>(find.byType(OutlinedButton)).enabled,
      isFalse,
    );
  });
}
