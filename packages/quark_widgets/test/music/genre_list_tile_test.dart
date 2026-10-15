import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A genre row, guarding its stable name key and singular count copy.
void main() {
  testBothViewports('renders the genre and reports its name', (
    tester,
    size,
  ) async {
    final selected = <String>[];
    await pumpAt(
      tester,
      GenreListTile(name: 'Jazz', trackCount: 312, onTap: selected.add),
      size: size,
    );

    expect(find.text('Jazz'), findsOneWidget);
    expect(find.text('312 tracks'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('music_genre_Jazz')));
    await tester.pump();

    expect(selected, ['Jazz']);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('uses singular copy and survives a long genre', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      GenreListTile(
        name: 'A genre name assembled from many overlapping traditions ' * 20,
        trackCount: 1,
        onTap: (_) {},
      ),
      size: size,
    );

    expect(find.text('1 track'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final (brightness, tokens) in [
    (Brightness.dark, QuarkTokens.dark),
    (Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$brightness: count color comes from tokens', (tester) async {
      await pumpAt(
        tester,
        GenreListTile(name: 'Jazz', trackCount: 312, onTap: (_) {}),
        brightness: brightness,
      );

      expect(
        tester.widget<Text>(find.text('312 tracks')).style?.color,
        tokens.mutedForeground,
      );
    });
  }
}
