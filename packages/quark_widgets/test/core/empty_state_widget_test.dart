import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testWidgets('omits the optional parts when they are not given', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const EmptyStateWidget(icon: Icons.folder, headline: 'Nothing here'),
      size: narrowViewport,
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
    // Icon plus headline, and nothing else.
    expect(find.byType(Text), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });

  testBothViewports('scrolls instead of overflowing a short space', (
    tester,
    size,
  ) async {
    // #2022: a card over a phone's listing left the empty state less height
    // than it needs, and its column overflowed.
    await pumpAt(
      tester,
      Align(
        alignment: Alignment.topCenter,
        child: SizedBox(
          height: 120,
          child: EmptyStateWidget(
            icon: Icons.folder,
            headline: 'Nothing here',
            subtext: 'Upload a file to get started.',
            action: FilledButton(onPressed: () {}, child: const Text('Upload')),
          ),
        ),
      ),
      size: size,
    );

    expect(find.text('Upload a file to get started.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
