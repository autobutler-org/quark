import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/music_album_controller.dart';
import 'package:quark/controllers/music_artist_controller.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/job.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_listing.dart';
import 'package:quark/models/music_play.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/pages/music_album_page.dart';
import 'package:quark/pages/music_artist_page.dart';
import 'package:quark/pages/music_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' as tap;

const _song = MusicTrack(
  relPath: 'music/Blue/01 All I Want.flac',
  serial: 'USB1',
  title: 'All I Want',
  artist: 'Joni Mitchell',
  albumArtist: 'Joni Mitchell',
  album: 'Blue',
  albumKey: 'k1',
  genre: 'Folk',
  year: 1971,
  durationMs: 214000,
);

/// The Music page and its album and artist drill-downs (#3283), through
/// the real routes: tabs with their own URLs, the genre filter in the
/// query, the empty and scanning library, search, and opening a song in
/// the file viewer.
void main() {
  late List<MusicTrack> library;
  late MusicStatus status;
  late int scansRequested;
  late StreamController<FileEvent> events;
  late List<MusicPlay> played;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    library = [_song, const MusicTrack(relPath: 'other.mp3', title: 'Other')];
    status = const MusicStatus(trackCount: 2);
    scansRequested = 0;
    played = [];
    events = StreamController<FileEvent>.broadcast();
    AppSettings.instance.isAdmin.value = false;
  });
  tearDown(() => events.close());

  Future<MusicListing<MusicTrack>> listTracks({
    String? albumKey,
    String? artist,
    String? genre,
    String? sort,
    bool descending = false,
    int offset = 0,
    int limit = 200,
  }) async {
    final tracks = library
        .where(
          (t) =>
              (genre == null || t.genre == genre) &&
              (albumKey == null || t.albumKey == albumKey) &&
              (artist == null || t.albumArtist == artist),
        )
        .toList();
    return MusicListing(items: tracks, total: tracks.length);
  }

  Future<MusicListing<MusicAlbum>> listAlbums({
    String? artist,
    int offset = 0,
    int limit = 200,
  }) async => library.isEmpty
      ? const MusicListing.empty()
      : const MusicListing(
          items: [
            MusicAlbum(
              albumKey: 'k1',
              title: 'Blue',
              albumArtist: 'Joni Mitchell',
              trackCount: 1,
            ),
          ],
          total: 1,
        );

  Future<GoRouter> visit(WidgetTester tester, String location) async {
    final controller = MusicController(
      status: () async => status,
      listTracks: listTracks,
      listAlbums: listAlbums,
      listArtists: ({int offset = 0, int limit = 200}) async =>
          const MusicListing(
            items: [MusicArtist(name: 'Joni Mitchell', albumCount: 1)],
            total: 1,
          ),
      listGenres: () async => const [MusicGenre(name: 'Folk', trackCount: 1)],
      search: (q) async => [
        const MusicSearchHit(track: _song, snippet: '<b>All</b> I Want'),
      ],
      rescan: () async {
        scansRequested++;
        return Job(
          id: 1,
          kind: 'music_rescan',
          name: '',
          status: JobStatus.pending,
          createdAt: DateTime.utc(2026),
        );
      },
      history: ({String sort = 'recent', int limit = 10}) async => played,
      events: events.stream,
      searchDebounce: Duration.zero,
    );
    addTearDown(controller.dispose);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '${AppRoutes.music}/albums/:albumKey',
          builder: (_, state) {
            final key = state.pathParameters['albumKey']!;
            return MusicAlbumPage(
              albumKey: key,
              controller: MusicAlbumController(
                albumKey: key,
                listTracks: listTracks,
                events: events.stream,
              ),
            );
          },
        ),
        GoRoute(
          path: AppRoutes.musicArtistPath,
          builder: (_, state) {
            final name = state.uri.queryParameters['name'] ?? '';
            return MusicArtistPage(
              name: name,
              controller: MusicArtistController(
                name: name,
                listAlbums: listAlbums,
                listTracks: listTracks,
                events: events.stream,
              ),
            );
          },
        ),
        ...tabbedRoutes(
          path: AppRoutes.music,
          tabs: MusicTab.values,
          builder: (tab, onTabSelected) => Builder(
            builder: (context) => MusicPage(
              tab: tab,
              onTabSelected: onTabSelected,
              genre: GoRouterState.of(context).uri.queryParameters['genre'],
              controller: controller,
            ),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.viewFile}/:path(.*)',
          builder: (_, state) => Text('viewer ${state.uri}'),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        theme: QuarkTheme.light(themeColor: QuarkThemeColor.classic),
        routerConfig: router,
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  String at(GoRouter router) =>
      router.routerDelegate.currentConfiguration.uri.toString();

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('lists songs and opens one in the player ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.music);

      expect(at(router), '/music/songs');
      expect(find.text('All I Want'), findsOneWidget);
      expect(find.text('Other'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(find.byKey(ValueKey('music_track_${_song.relPath}')));
      await tester.pumpAndSettle();
      final viewer = Uri.parse(at(router));
      expect(viewer.path, '/view/music/Blue/01%20All%20I%20Want.flac');
      expect(viewer.queryParameters['serial'], 'USB1');
      expect(viewer.queryParameters['from'], '/music/songs');
    });

    // #3284: Songs opens with the user's history, whose songs play too.
    testWidgets('Recently and Most played head Songs ($name)', (tester) async {
      tap.setViewport(tester, size);
      played = [MusicPlay(track: _song, playCount: 3)];
      final router = await visit(tester, AppRoutes.music);

      final recent = find.byKey(const ValueKey('section_recently_played'));
      expect(recent, findsOneWidget);
      expect(find.byKey(const ValueKey('section_most_played')), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(
        find.descendant(
          of: recent,
          matching: find.byKey(ValueKey('music_track_${_song.relPath}')),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        Uri.parse(at(router)).path,
        '/view/music/Blue/01%20All%20I%20Want.flac',
      );
    });

    testWidgets('no history, or a genre, shows only songs ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await visit(tester, AppRoutes.music);
      expect(
        find.byKey(const ValueKey('section_recently_played')),
        findsNothing,
      );

      played = [MusicPlay(track: _song, playCount: 1)];
      await visit(tester, AppRoutes.musicGenre('Folk'));
      expect(
        find.byKey(const ValueKey('section_recently_played')),
        findsNothing,
      );
      expect(find.text('All I Want'), findsOneWidget);
    });

    testWidgets('each tab has its own URL ($name)', (tester) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.musicTab(MusicTab.albums));
      expect(find.byKey(const ValueKey('music_album_k1')), findsOneWidget);

      await tester.tap(find.text('Artists'));
      await tester.pumpAndSettle();
      expect(at(router), '/music/artists');
      expect(
        find.byKey(const ValueKey('music_artist_Joni Mitchell')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('an album opens its page, and back returns ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.musicTab(MusicTab.albums));
      await tester.tap(find.byKey(const ValueKey('music_album_k1')));
      await tester.pumpAndSettle();

      expect(at(router), '/music/albums/k1');
      expect(find.byKey(const ValueKey('music_album_page')), findsOneWidget);
      expect(find.text('All I Want'), findsOneWidget);
      expect(find.text('Other'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(at(router), '/music/albums');
    });

    testWidgets('an artist opens their albums and songs ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.musicTab(MusicTab.artists));
      await tester.tap(
        find.byKey(const ValueKey('music_artist_Joni Mitchell')),
      );
      await tester.pumpAndSettle();

      expect(at(router), '/music/artist?name=Joni+Mitchell');
      expect(find.byKey(const ValueKey('music_artist_page')), findsOneWidget);
      expect(find.byKey(const ValueKey('music_album_k1')), findsOneWidget);
      expect(find.text('All I Want'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a genre narrows Songs until cleared ($name)', (tester) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.musicTab(MusicTab.genres));
      await tester.tap(find.byKey(const ValueKey('music_genre_Folk')));
      await tester.pumpAndSettle();

      expect(at(router), '/music/songs?genre=Folk');
      expect(find.byKey(const ValueKey('music_genre_filter')), findsOneWidget);
      expect(find.text('All I Want'), findsOneWidget);
      expect(find.text('Other'), findsNothing);

      await tester.tap(find.byTooltip('Show every song'));
      await tester.pumpAndSettle();
      expect(at(router), '/music/songs');
      expect(find.text('Other'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('search replaces the tabs with its hits ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      await visit(tester, AppRoutes.music);
      await tester.enterText(
        find.byKey(const ValueKey('music_search_field')),
        'all',
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuarkTabView), findsNothing);
      // The Quark's highlight markers are not shown as text.
      expect(find.text('All I Want'), findsNWidgets(2));
      expect(find.textContaining('<b>'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('music_search_clear')));
      await tester.pumpAndSettle();
      expect(find.byType(QuarkTabView), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an empty library offers an admin a scan ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      library = [];
      status = const MusicStatus();
      AppSettings.instance.isAdmin.value = true;
      await visit(tester, AppRoutes.music);

      expect(find.text('No music yet'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('music_scan')));
      await tester.pump();
      await tester.pump();
      expect(scansRequested, 1);
      expect(find.text('Scanning your music'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty library offers anyone else no scan', (tester) async {
    library = [];
    status = const MusicStatus();
    await visit(tester, AppRoutes.music);
    expect(find.text('No music yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('music_scan')), findsNothing);
  });

  testWidgets('a library event fetches the library again', (tester) async {
    await visit(tester, AppRoutes.music);
    expect(find.text('New song'), findsNothing);
    library = [
      ...library,
      const MusicTrack(relPath: 'n.mp3', title: 'New song'),
    ];
    events.add(const FileEvent(kind: 'music_library_changed', path: ''));
    await tester.pumpAndSettle();
    expect(find.text('New song'), findsOneWidget);
  });
}
