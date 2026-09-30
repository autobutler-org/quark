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

  testBothViewports('is a 48 pixel target (#2605)', (tester, size) async {
    await pumpAt(
      tester,
      QuarkBrandButton(label: 'Files', onTap: () {}),
      size: size,
    );

    await expectTapTargetsMeetGuideline(tester);
  });

  testWidgets('survives 200% text on a phone (#2606)', (tester) async {
    await expectSurvivesLargeText(
      tester,
      Center(
        child: SizedBox(
          width: QuarkBrandButton.preferredWidth,
          child: QuarkBrandButton(label: 'Files', onTap: () {}),
        ),
      ),
    );
  });
}
