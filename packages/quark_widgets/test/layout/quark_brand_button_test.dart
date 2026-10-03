import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('shows the label and calls back on tap', (
    tester,
    size,
  ) async {
    var taps = 0;
    await pumpAt(
      tester,
      QuarkBrandButton(label: 'Files', onTap: () => taps++),
      size: size,
    );

    expect(find.text('Files'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.storage_rounded), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('brand_button')));
    await tester.pump();

    expect(taps, 1);
  });

  testBothViewports('renders the icon it is given', (tester, size) async {
    await pumpAt(
      tester,
      QuarkBrandButton(
        label: 'Photos',
        icon: QuarkIcons.photo_library_outlined,
        onTap: () {},
      ),
      size: size,
    );

    expect(find.byIcon(QuarkIcons.photo_library_outlined), findsOneWidget);
  });

  testWidgets('lays out on a narrow phone without overflowing', (tester) async {
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.centerLeft,
        child: QuarkBrandButton(label: 'Devices', onTap: () {}),
      ),
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(QuarkBrandButton)).width,
      lessThanOrEqualTo(narrowViewport.width),
    );
  });

  testWidgets('clips a page name too long for its slot', (tester) async {
    // The button lives in an app bar leading slot of a fixed width, so a long
    // label has to be cut rather than overflow the bar.
    await pumpAt(
      tester,
      SizedBox(
        width: QuarkBrandButton.preferredWidth,
        child: QuarkBrandButton(
          label: 'Software Bill of Materials' * 4,
          onTap: () {},
        ),
      ),
      size: narrowViewport,
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byType(QuarkBrandButton)).width,
      lessThanOrEqualTo(QuarkBrandButton.preferredWidth),
    );
  });

  testBothViewports('is a 48dp button to a screen reader', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Center(
        child: QuarkBrandButton(label: 'Files', onTap: () {}),
      ),
      size: size,
    );
    final handle = tester.ensureSemantics();

    final button = find.byKey(const ValueKey('brand_button'));
    expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    expect(tester.getSemantics(button).flagsCollection.isButton, isTrue);
    handle.dispose();
    await expectTapTargetGuidelines(tester);
  });

  // #2606: the label grows past the 28 pixel badge beside it.
  testLargeText('fits its label', (tester, size) async {
    await pumpAt(
      tester,
      Center(
        child: SizedBox(
          width: QuarkBrandButton.preferredWidth,
          child: QuarkBrandButton(label: 'Files', onTap: () {}),
        ),
      ),
      size: size,
    );

    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
    await expectTapTargetGuidelines(tester);
  });
}
