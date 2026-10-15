import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// Search results, covering every caller-owned state and delegated track tap.
void main() {
  const results = [
    MusicSearchResult(
      track: MusicTrackItem(
        path: 'jazz/so-what.flac',
        title: 'So What',
        artist: 'Miles Davis',
        album: 'Kind of Blue',
      ),
      snippet: 'So What — Miles Davis',
    ),
    MusicSearchResult(
      track: MusicTrackItem(
        path: 'jazz/blue-in-green.flac',
        title: 'Blue in Green',
        artist: 'Miles Davis',
        album: 'Kind of Blue',
      ),
      snippet: 'Blue in Green — Kind of Blue',
    ),
  ];

  testBothViewports('shows only a loader while searching', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const MusicSearchResults(results: results, isLoading: true),
      size: size,
    );

    expect(find.byType(QuarkLoader), findsOneWidget);
    expect(
      find.byKey(const ValueKey('music_track_jazz/so-what.flac')),
      findsNothing,
    );
    expect(find.text('No matches'), findsNothing);
  });

  testBothViewports('renders only the caller-provided error', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const MusicSearchResults(
        results: results,
        error: 'The library is unavailable.',
      ),
      size: size,
    );

    expect(find.text('The library is unavailable.'), findsOneWidget);
    expect(find.byType(QuarkLoader), findsNothing);
    expect(
      find.byKey(const ValueKey('music_track_jazz/so-what.flac')),
      findsNothing,
    );
  });

  testBothViewports('prompts before a query and explains no matches', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      const Column(
        children: [
          Expanded(child: MusicSearchResults(results: [])),
          Expanded(
            child: MusicSearchResults(results: [], query: 'obscure'),
          ),
        ],
      ),
      size: size,
    );

    expect(find.text('Search your music'), findsOneWidget);
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Nothing matched “obscure”.'), findsOneWidget);
  });

  testBothViewports('renders results and reports the selected track', (
    tester,
    size,
  ) async {
    final selected = <MusicTrackItem>[];
    await pumpAt(
      tester,
      SingleChildScrollView(
        child: MusicSearchResults(
          results: results,
          coverBuilder: (context, result) => Text(result.track.title),
          onTrackTap: selected.add,
        ),
      ),
      size: size,
    );

    for (final result in results) {
      expect(
        find.byKey(ValueKey('music_track_${result.track.path}')),
        findsOneWidget,
      );
      expect(find.text(result.snippet), findsOneWidget);
    }
    await tester.tap(
      find.byKey(const ValueKey('music_track_jazz/blue-in-green.flac')),
    );
    await tester.pump();

    expect(selected, [same(results[1].track)]);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('survives many long results', (tester, size) async {
    final many = [
      for (var index = 0; index < 100; index++)
        MusicSearchResult(
          track: MusicTrackItem(
            path: '$index.flac',
            title: 'A very long matching title ' * 10,
            artist: 'A very long artist ' * 10,
          ),
          snippet: 'A very long snippet ' * 20,
        ),
    ];
    await pumpAt(
      tester,
      SingleChildScrollView(child: MusicSearchResults(results: many)),
      size: size,
    );

    expect(tester.takeException(), isNull);
  });

  for (final (brightness, tokens) in [
    (Brightness.dark, QuarkTokens.dark),
    (Brightness.light, QuarkTokens.light),
  ]) {
    testWidgets('$brightness: snippets use the muted token', (tester) async {
      await pumpAt(
        tester,
        const MusicSearchResults(results: results),
        brightness: brightness,
      );

      expect(
        tester.widget<Text>(find.text(results.first.snippet)).style?.color,
        tokens.mutedForeground,
      );
    });
  }
}
