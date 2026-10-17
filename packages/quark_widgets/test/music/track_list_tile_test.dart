import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// A song row, guarding long metadata, duration formatting, and its path key.
void main() {
  const track = MusicTrackItem(
    path: 'Miles Davis/Kind of Blue/01 So What.flac',
    title: 'So What',
    artist: 'Miles Davis',
    album: 'Kind of Blue',
    duration: Duration(minutes: 9, seconds: 22),
  );

  testBothViewports('renders metadata and reports the tapped track', (
    tester,
    size,
  ) async {
    final tapped = <MusicTrackItem>[];
    await pumpAt(
      tester,
      TrackListTile(
        item: track,
        coverBuilder: (context) => const Text('cover'),
        onTap: tapped.add,
      ),
      size: size,
    );

    expect(find.text('So What'), findsOneWidget);
    expect(find.text('Miles Davis · Kind of Blue'), findsOneWidget);
    expect(find.text('9:22'), findsOneWidget);
    expect(find.text('cover'), findsOneWidget);
    await tester.tap(
      find.byKey(
        const ValueKey('music_track_Miles Davis/Kind of Blue/01 So What.flac'),
      ),
    );
    await tester.pump();

    expect(tapped, [same(track)]);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('survives long metadata without overflowing', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      TrackListTile(
        item: MusicTrackItem(
          path: 'long.flac',
          title: 'A title that keeps going ' * 20,
          artist: 'An artist with an exceptionally long stage name ' * 10,
          album: 'An album with a deluxe anniversary subtitle ' * 10,
          duration: Duration(hours: 1, minutes: 2, seconds: 3),
        ),
        onTap: (_) {},
      ),
      size: size,
    );

    expect(find.text('1:02:03'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('uses the path in its documented key', (tester) async {
    await pumpAt(tester, TrackListTile(item: track, onTap: (_) {}));

    expect(
      find.byKey(
        const ValueKey('music_track_Miles Davis/Kind of Blue/01 So What.flac'),
      ),
      findsOneWidget,
    );
  });

  for (final brightness in [Brightness.dark, Brightness.light]) {
    testWidgets('$brightness: metadata follows the active token set', (
      tester,
    ) async {
      await pumpAt(
        tester,
        TrackListTile(item: track, onTap: (_) {}),
        brightness: brightness,
      );
      final tokens = brightness == Brightness.dark
          ? QuarkTokens.dark
          : QuarkTokens.light;

      expect(
        tester.widget<Text>(find.text('9:22')).style?.color,
        tokens.mutedForeground,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
