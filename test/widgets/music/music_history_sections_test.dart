import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/music_play.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/widgets/music/music_history_sections.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../../support/tap_target_guidelines.dart' as tap;

MusicPlay _play(String path, String title) => MusicPlay(
  track: MusicTrack(
    relPath: path,
    title: title,
    artist: 'A long artist name that has to fit a phone',
    album: 'An album with a long title as well',
    durationMs: 241000,
  ),
  playCount: 2,
);

/// Songs' Recently played and Most played (#3284).
void main() {
  Future<List<MusicTrackItem>> pump(
    WidgetTester tester, {
    required List<MusicPlay> recent,
    required List<MusicPlay> mostPlayed,
  }) async {
    final tapped = <MusicTrackItem>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        home: Scaffold(
          body: SingleChildScrollView(
            child: MusicHistorySections(
              recent: recent,
              mostPlayed: mostPlayed,
              onTrackTap: tapped.add,
            ),
          ),
        ),
      ),
    );
    return tapped;
  }

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('shows both sections, each song tappable ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final tapped = await pump(
        tester,
        recent: [_play('a.mp3', 'Alpha'), _play('b.mp3', 'Beta')],
        mostPlayed: [_play('b.mp3', 'Beta')],
      );

      final recent = find.byKey(const ValueKey('section_recently_played'));
      final most = find.byKey(const ValueKey('section_most_played'));
      expect(recent, findsOneWidget);
      expect(most, findsOneWidget);
      expect(find.text('Beta'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(
        find.descendant(
          of: most,
          matching: find.byKey(const ValueKey('music_track_b.mp3')),
        ),
      );
      expect(tapped.single.path, 'b.mp3');
    });

    testWidgets('leaves out an empty section ($name)', (tester) async {
      tap.setViewport(tester, size);
      await pump(tester, recent: [_play('a.mp3', 'Alpha')], mostPlayed: []);
      expect(
        find.byKey(const ValueKey('section_recently_played')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('section_most_played')), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
