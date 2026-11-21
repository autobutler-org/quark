import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_album.dart';
import 'package:quark/models/music_artist.dart';
import 'package:quark/models/music_genre.dart';
import 'package:quark/models/music_status.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/pages/music_album_page.dart';
import 'package:quark/pages/music_artist_page.dart';
import 'package:quark/pages/music_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/services/music_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' as tap;

const _soWhat = MusicTrack(
  relPath: 'Music/Kind of Blue/01 So What.flac',
  title: 'So What',
  artist: 'Miles Davis',
  albumArtist: 'Miles Davis',
  album: 'Kind of Blue',
  albumKey: 'kob',
  genre: 'Jazz',
  durationMs: 562000,
);

const _paranoid = MusicTrack(
  relPath: 'Music/Paranoid/02 Paranoid.mp3',
  serial: 'STICK',
  title: 'Paranoid',
  artist: 'Black Sabbath',
  album: 'Paranoid',
  albumKey: 'par',
  genre: 'Metal',
);

/// The Music pages (#3283): the library's four tabs, search, the empty and
/// scanning state, and the album and artist pages, at a phone's and a
/// desktop's width.
void main() {
  late List<MusicTrack> library;
  late MusicStatus status;
  late Object? searchFailure;
  late StreamController<FileEvent> events;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.refreshInterval.value = 15;
    AppSettings.instance.isAdmin.value = false;
    library = const [_soWhat, _paranoid];
    status = const MusicStatus(trackCount: 2);
    searchFailure = null;
    events = StreamController<FileEvent>.broadcast();
  });
  tearDown(() => events.close());

  MusicController controller({String? albumKey, String? artist}) {
    final c = MusicController(
      albumKey: albumKey,
      artist: artist,
      listTracks: ({albumKey, artist, genre}) async => [
        for (final t in library)
          if ((albumKey == null || t.albumKey == albumKey) &&
              (artist == null || t.albumArtist == artist) &&
              (genre == null || t.genre == genre))
            t,
      ],
      listAlbums: ({artist}) async => [
        if (artist == null || artist == 'Miles Davis')
          const MusicAlbum(
            key: 'kob',
            title: 'Kind of Blue',
            albumArtist: 'Miles Davis',
            trackCount: 1,
            year: 1959,
          ),
      ],
      listArtists: () async => const [
        MusicArtist(name: 'Miles Davis', albumCount: 1, trackCount: 1),
      ],
      listGenres: () async => const [
        MusicGenre(name: 'Jazz', trackCount: 1),
        MusicGenre(name: 'Metal', trackCount: 1),
      ],
      status: () async => status,
      search: (query) async {
        final f = searchFailure;
        if (f != null) throw f;
        final MusicSearchHit hit = (
          track: _soWhat,
          snippet: 'title: <b>So</b> What',
        );
        return [hit];
      },
      rescan: () async {},
      events: events.stream,
      searchDelay: Duration.zero,
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<GoRouter> visit(
    WidgetTester tester,
    String location, {
    bool settle = true,
  }) async {
    final library = controller();
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '${AppRoutes.music}/albums/:albumKey',
          builder: (_, state) => MusicAlbumPage(
            albumKey: state.pathParameters['albumKey']!,
            controller: controller(albumKey: state.pathParameters['albumKey']),
          ),
        ),
        GoRoute(
          path: '${AppRoutes.music}/artists/:name',
          builder: (_, state) => MusicArtistPage(
            name: state.pathParameters['name']!,
            controller: controller(artist: state.pathParameters['name']),
          ),
        ),
        ...tabbedRoutes(
          path: AppRoutes.music,
          tabs: MusicTab.values,
          builder: (tab, onTabSelected) => MusicPage(
            tab: tab,
            onTabSelected: onTabSelected,
            controller: library,
          ),
        ),
        GoRoute(
          path: '${AppRoutes.viewFile}/:path(.*)',
          builder: (_, state) => Text('viewer ${state.pathParameters['path']}'),
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
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
      await tester.pump();
    }
    return router;
  }

  String at(GoRouter r) => r.routerDelegate.currentConfiguration.uri.toString();

  for (final (name, size) in [
    ('narrow', tap.narrowViewport),
    ('wide', tap.wideViewport),
  ]) {
    testWidgets('lists the songs and plays one ($name)', (tester) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.music);

      expect(at(router), '/music/songs');
      expect(find.text('So What'), findsOneWidget);
      expect(find.text('Paranoid'), findsOneWidget);
      expect(find.text('9:22'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(
        find.byKey(
          const ValueKey('music_track_Music/Paranoid/02 Paranoid.mp3'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        at(router),
        '/view/Music/Paranoid/02%20Paranoid.mp3'
        '?serial=STICK&from=/music/songs',
      );
    });

    testWidgets('opens an album from the Albums tab ($name)', (tester) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.musicTab(MusicTab.albums));

      expect(find.text('Kind of Blue'), findsOneWidget);
      expect(find.text('Miles Davis · 1959'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(find.byKey(const ValueKey('music_album_kob')));
      await tester.pumpAndSettle();
      expect(at(router), '/music/albums/kob');
      expect(find.text('So What'), findsOneWidget);
      expect(find.text('Paranoid'), findsNothing);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(find.byKey(const ValueKey('music_back')));
      await tester.pumpAndSettle();
      expect(at(router), '/music/albums');
    });

    testWidgets('opens an artist from the Artists tab ($name)', (tester) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.musicTab(MusicTab.artists));

      await tester.tap(find.byKey(const ValueKey('music_artist_Miles Davis')));
      await tester.pumpAndSettle();
      expect(at(router), '/music/artists/Miles%20Davis');
      expect(find.text('Kind of Blue'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tap.expectTapTargetGuidelines(tester);

      await tester.tap(find.byKey(const ValueKey('tab_songs')));
      await tester.pumpAndSettle();
      expect(find.text('So What'), findsOneWidget);
      expect(find.text('Paranoid'), findsNothing);
    });

    testWidgets('a genre filters the songs ($name)', (tester) async {
      tap.setViewport(tester, size);
      final router = await visit(tester, AppRoutes.musicTab(MusicTab.genres));

      await tester.tap(find.byKey(const ValueKey('music_genre_Metal')));
      await tester.pumpAndSettle();
      expect(at(router), '/music/songs');
      expect(find.text('Genre: Metal'), findsOneWidget);
      expect(find.text('Paranoid'), findsOneWidget);
      expect(find.text('So What'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('music_genre_filter_clear')));
      await tester.pumpAndSettle();
      expect(find.text('So What'), findsOneWidget);
    });

    testWidgets('an empty library says a scan is under way ($name)', (
      tester,
    ) async {
      tap.setViewport(tester, size);
      library = const [];
      status = const MusicStatus(scanJobId: 3);
      // The loader spins, so this does not settle.
      await visit(tester, AppRoutes.music, settle: false);
      expect(find.text('Scanning your music'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('an empty library offers an admin a scan', (tester) async {
    tap.setViewport(tester, tap.narrowViewport);
    library = const [];
    status = const MusicStatus();
    AppSettings.instance.isAdmin.value = true;
    await visit(tester, AppRoutes.music);

    expect(find.text('No music yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('music_scan')), findsOneWidget);
  });

  testWidgets('a member gets no scan button', (tester) async {
    tap.setViewport(tester, tap.narrowViewport);
    library = const [];
    status = const MusicStatus();
    await visit(tester, AppRoutes.music);

    expect(find.text('No music yet'), findsOneWidget);
    expect(find.byKey(const ValueKey('music_scan')), findsNothing);
  });

  testWidgets('searches, and says when the Quark cannot', (tester) async {
    tap.setViewport(tester, tap.narrowViewport);
    await visit(tester, AppRoutes.music);

    await tester.enterText(find.byKey(const ValueKey('music_search')), 'so');
    await tester.pumpAndSettle();
    expect(find.text('So What'), findsOneWidget);
    expect(find.text('Paranoid'), findsNothing);
    // The matched terms' <b> tags are not drawn.
    expect(find.text('title: So What'), findsOneWidget);

    searchFailure = ApiException(501, 'search music');
    await tester.enterText(find.byKey(const ValueKey('music_search')), 'sow');
    await tester.pumpAndSettle();
    expect(find.text("Your Quark doesn't support that yet."), findsOneWidget);
  });

  testWidgets('the library changing on the Quark lists it again', (
    tester,
  ) async {
    tap.setViewport(tester, tap.narrowViewport);
    await visit(tester, AppRoutes.music);
    library = const [_soWhat];

    events.add(const FileEvent(kind: 'music_library_changed', path: ''));
    await tester.pumpAndSettle();
    expect(find.text('Paranoid'), findsNothing);
    expect(find.text('So What'), findsOneWidget);
  });
}
