import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// An album grid card, including its cover slot and stable album-key callback.
void main() {
  Widget tile({String title = 'Kind of Blue', ValueChanged<String>? onTap}) =>
      SizedBox(
        width: 220,
        child: AlbumGridTile(
          albumKey: 'kind-of-blue',
          title: title,
          albumArtist: 'Miles Davis',
          year: 1959,
          trackCount: 5,
          coverBuilder: (context) => const Text('cover'),
          onTap: onTap ?? (_) {},
        ),
      );

  testBothViewports('renders album details and reports the album key', (
    tester,
    size,
  ) async {
    final selected = <String>[];
    await pumpAt(
      tester,
      Center(child: tile(onTap: selected.add)),
      size: size,
    );

    expect(find.text('Kind of Blue'), findsOneWidget);
    expect(find.text('Miles Davis · 1959'), findsOneWidget);
    expect(find.text('5 tracks'), findsOneWidget);
    expect(find.text('cover'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('music_album_kind-of-blue')));
    await tester.pump();

    expect(selected, ['kind-of-blue']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('survives a long title and artist', (tester, size) async {
    await pumpAt(
      tester,
      Center(child: tile(title: 'A very long album title ' * 20)),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (brightness, tokens) in [
    (Brightness.dark, QuarkTokens.dark),
    (Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$brightness: card colors come from tokens', (tester) async {
      await pumpAt(tester, Center(child: tile()), brightness: brightness);

      final box = tester.widget<DecoratedBox>(
        find.byKey(const ValueKey('music_album_surface_kind-of-blue')),
      );
      final decoration = box.decoration as BoxDecoration;
      expect(decoration.color, tokens.card);
      expect(decoration.border, Border.all(color: tokens.border));
    });
  }
}
