import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Cover art shared by the music tiles, including its network-free fallback.
void main() {
  testBothViewports('shows a token-colored placeholder without cover art', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const Center(
        child: SizedBox.square(dimension: 160, child: MusicCoverArt()),
      ),
      size: size,
    );

    expect(find.byIcon(QuarkIcons.disc_full), findsOneWidget);
    final box = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('music_cover_surface')),
    );
    expect((box.decoration as BoxDecoration).color, QuarkTokens.dark.sidebar);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('renders coverBuilder instead of the placeholder', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      Center(
        child: SizedBox.square(
          dimension: 160,
          child: MusicCoverArt(
            semanticLabel: 'Cover for Kind of Blue',
            coverBuilder: (context) => const Text('painted cover'),
          ),
        ),
      ),
      size: size,
    );

    expect(find.text('painted cover'), findsOneWidget);
    expect(find.byIcon(QuarkIcons.disc_full), findsNothing);
    expect(find.bySemanticsLabel('Cover for Kind of Blue'), findsOneWidget);
  });

  for (final (label, brightness, tokens) in [
    ('dark', Brightness.dark, QuarkTokens.dark),
    ('light', Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$label: placeholder colors come from tokens', (tester) async {
      await pumpAt(
        tester,
        const Center(
          child: SizedBox.square(dimension: 120, child: MusicCoverArt()),
        ),
        brightness: brightness,
      );

      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('music_cover_surface')),
      );
      expect((box.decoration as BoxDecoration).color, tokens.sidebar);
      expect(
        tester.widget<Icon>(find.byIcon(QuarkIcons.disc_full)).color,
        tokens.mutedForeground,
      );
    });
  }
}
