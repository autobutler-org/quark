import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// An artist row, guarding its count copy, cover slot, key, and callback.
void main() {
  testBothViewports('renders the artist and reports its name', (
    tester,
    size,
  ) async {
    final selected = <String>[];
    await pumpAt(
      tester,
      ArtistListTile(
        name: 'Nina Simone',
        albumCount: 8,
        trackCount: 74,
        coverBuilder: (context) => const Text('cover'),
        onTap: selected.add,
      ),
      size: size,
    );

    expect(find.text('Nina Simone'), findsOneWidget);
    expect(find.text('8 albums · 74 tracks'), findsOneWidget);
    expect(find.text('cover'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('music_artist_Nina Simone')));
    await tester.pump();

    expect(selected, ['Nina Simone']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('uses singular count copy and survives long names', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      ArtistListTile(
        name: 'An artist with an extremely long performance name ' * 20,
        albumCount: 1,
        trackCount: 1,
        onTap: (_) {},
      ),
      size: size,
    );

    expect(find.text('1 album · 1 track'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (brightness, tokens) in [
    (Brightness.dark, QuarkTokens.dark),
    (Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$brightness: count color comes from tokens', (tester) async {
      await pumpAt(
        tester,
        ArtistListTile(
          name: 'Nina Simone',
          albumCount: 8,
          trackCount: 74,
          onTap: (_) {},
        ),
        brightness: brightness,
      );

      expect(
        tester.widget<Text>(find.text('8 albums · 74 tracks')).style?.color,
        tokens.mutedForeground,
      );
    });
  }
}
