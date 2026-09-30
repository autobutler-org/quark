import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

void main() {
  testBothViewports('renders the headline alone', (tester, size) async {
    await pumpAt(
      tester,
      const EmptyStateWidget(icon: Icons.folder, headline: 'Nothing here'),
      size: size,
    );

    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.byIcon(Icons.folder), findsOneWidget);
  });

  testBothViewports('renders the subtext when given one', (tester, size) async {
    await pumpAt(
      tester,
      const EmptyStateWidget(
        icon: Icons.folder,
        headline: 'Nothing here',
        subtext: 'Upload a file to get started.',
      ),
      size: size,
    );

    expect(find.text('Upload a file to get started.'), findsOneWidget);
  });

  // Half-alpha onSurface was 2.5–3.3:1; the muted token holds 4.5:1 (#2602).
  for (final brightness in Brightness.values) {
    testWidgets('subtext uses the muted token in ${brightness.name}', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const EmptyStateWidget(
          icon: Icons.folder,
          headline: 'Nothing here',
          subtext: 'Upload a file to get started.',
        ),
        brightness: brightness,
      );

      final tokens = brightness == Brightness.dark
          ? QuarkTokens.dark
          : QuarkTokens.light;
      expect(
        tester
            .widget<Text>(find.text('Upload a file to get started.'))
            .style
            ?.color,
        tokens.mutedForeground,
      );
    });
  }

  testBothViewports('renders and wires the action', (tester, size) async {
    var taps = 0;
    await pumpAt(
      tester,
      EmptyStateWidget(
        icon: Icons.folder,
        headline: 'Nothing here',
        action: FilledButton(
          onPressed: () => taps++,
          child: const Text('Upload'),
        ),
      ),
      size: size,
    );

    await tester.tap(find.text('Upload'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('omits the optional parts when they are not given', (
    tester,
  ) async {
    await pumpAt(
      tester,
      const EmptyStateWidget(icon: Icons.folder, headline: 'Nothing here'),
      size: narrowViewport,
    );

    // Icon plus headline, and nothing else.
    expect(find.byType(Text), findsOneWidget);
    expect(find.byType(FilledButton), findsNothing);
  });
}
