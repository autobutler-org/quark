import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/unreachable_quark.dart';

/// #1746: with Demo mode on, the Photos page shows the bundled sample library
/// and talks to no Quark at all; with it off, nothing from the sample library
/// is rendered. Both halves matter — the second is the one that protects a
/// real user from seeing photos that are not theirs.
void main() {
  const desktopSize = Size(1400, 900);
  final settings = AppSettings.instance;

  late HttpOverrides? priorOverrides;
  // One recorder for the whole file: the app's http client outlives a test,
  // so it keeps the overrides it was created under.
  final recorder = _RecordingHttpOverrides();

  // The test platform is Android, so the page also asks photo_manager for the
  // device library. With no plugin behind the channel that call never answers
  // and the whole refresh hangs; denying it lets the page settle.
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          photoManager,
          (_) async => throw MissingPluginException(),
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManager, null);
  });

  setUp(() async {
    priorOverrides = HttpOverrides.current;
    recorder.requests.clear();
    HttpOverrides.global = recorder;
    await settings.addHost(
      HostEntry(name: 'Demo', hostAddress: 'http://quark.test'),
    );
  });

  tearDown(() async {
    HttpOverrides.global = priorOverrides;
    await settings.setDemoMode(false);
    while (settings.hosts.isNotEmpty) {
      await settings.removeHost(settings.hosts.length - 1);
    }
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// The Photos route alone, parsed the way `lib/router.dart` parses it, so
  /// albums can move the URL without the auth gate in the way.
  Future<GoRouter> pumpPhotosRoute(
    WidgetTester tester, {
    Size size = desktopSize,
    String location = AppRoutes.photos,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: AppRoutes.photos,
          builder: (context, state) => PhotosPage(
            album: state.uri.queryParameters[AppRoutes.photosAlbumParam],
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await settle(tester);
    return router;
  }

  Future<void> pumpPhotos(WidgetTester tester) async {
    tester.view.physicalSize = desktopSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: PhotosPage()));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Finder assetImages() => find.byWidgetPredicate(
    (w) => w is Image && w.image is AssetImage,
    description: 'an Image backed by a bundled asset',
  );

  testWidgets('shows the sample library without reaching the Quark', (
    tester,
  ) async {
    await settings.setDemoMode(true);

    await pumpPhotos(tester);

    expect(tester.takeException(), isNull);
    expect(
      assetImages(),
      findsNWidgets(DemoPhotosService.photos.length),
      reason: 'every sample photo gets a tile',
    );
    expect(find.text('Quark: ${DemoPhotosService.photos.length}'), findsOne);
    for (final album in DemoPhotosService.albums()) {
      expect(find.text(album.name), findsOneWidget, reason: album.name);
    }
    expect(find.text('No photos yet'), findsNothing);
    expect(
      recorder.requests,
      isEmpty,
      reason: 'demo mode must not touch the backend',
    );
  });

  // #2311: Photos selects through the same bar as Files and the trash — a
  // leading close button, the count, and Select all — not a Cancel of its own.
  testWidgets('selecting wears the shared selection bar', (tester) async {
    await settings.setDemoMode(true);
    await pumpPhotos(tester);

    await tester.tap(find.byKey(const ValueKey('photos_select')));
    await tester.pump();

    expect(find.byType(FileSelectionBar), findsOneWidget);
    expect(find.text('0 selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('file_selection_delete')), findsNothing);
    expect(find.text('Cancel'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('file_selection_toggle_all')));
    await tester.pump();
    expect(
      find.text('${DemoPhotosService.photos.length} selected'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('file_selection_cancel')));
    await tester.pump();
    expect(find.byType(FileSelectionBar), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // #1916: an album opens in place on the Photos page, and the URL follows.
  group('albums open in place', () {
    int count(int albumId) => DemoPhotosService.listAlbumItems(albumId).length;

    testWidgets('tapping an album keeps the page and shows its photos', (
      tester,
    ) async {
      await settings.setDemoMode(true);
      final router = await pumpPhotosRoute(tester);
      final hiking = DemoPhotosService.hikingAlbumId;

      await tester.tap(find.byKey(ValueKey('album_tile_$hiking')));
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(PhotosPage), findsOneWidget);
      expect(router.state.uri.toString(), '/photos?album=Hiking');
      expect(assetImages(), findsNWidgets(count(hiking)));
      expect(
        find.byType(PhotoCategoryList),
        findsNothing,
        reason: 'the categories filter the library, so they hide in an album',
      );
      expect(find.byKey(const ValueKey('photos_add_to_album')), findsOneWidget);
      expect(recorder.requests, isEmpty);

      await tester.tap(find.byKey(const ValueKey('album_sidebar_all_photos')));
      await settle(tester);

      expect(router.state.uri.toString(), AppRoutes.photos);
      expect(assetImages(), findsNWidgets(DemoPhotosService.photos.length));
      expect(find.byType(PhotoCategoryList), findsOneWidget);
    });

    testWidgets('a system album offers no Add Photos', (tester) async {
      await settings.setDemoMode(true);
      await pumpPhotosRoute(
        tester,
        location: AppRoutes.photosAlbum('Favorites'),
      );

      expect(
        assetImages(),
        findsNWidgets(count(DemoPhotosService.favoritesAlbumId)),
      );
      expect(find.byKey(const ValueKey('photos_add_to_album')), findsNothing);
    });

    testWidgets('a link to an album lands on it', (tester) async {
      await settings.setDemoMode(true);
      final trip = DemoPhotosService.summerTripAlbumId;
      final router = await pumpPhotosRoute(
        tester,
        location: AppRoutes.photosAlbum('Summer Trip'),
      );

      expect(assetImages(), findsNWidgets(count(trip)));
      expect(router.state.uri.toString(), '/photos?album=Summer%20Trip');
    });

    testWidgets('a link by id or in another case is rewritten to the name', (
      tester,
    ) async {
      await settings.setDemoMode(true);
      final trip = DemoPhotosService.summerTripAlbumId;
      for (final location in [
        AppRoutes.photosAlbum('$trip'),
        AppRoutes.photosAlbum('summer trip'),
      ]) {
        final router = await pumpPhotosRoute(tester, location: location);

        expect(assetImages(), findsNWidgets(count(trip)), reason: location);
        expect(
          router.state.uri.queryParameters[AppRoutes.photosAlbumParam],
          'Summer Trip',
          reason: location,
        );
      }
    });

    testWidgets('a link to an unknown album shows All photos', (tester) async {
      await settings.setDemoMode(true);
      final router = await pumpPhotosRoute(
        tester,
        location: AppRoutes.photosAlbum('999'),
      );

      expect(assetImages(), findsNWidgets(DemoPhotosService.photos.length));
      expect(router.state.uri.toString(), AppRoutes.photos);
    });

    testWidgets('on a narrow screen, picking an album scrolls to the grid', (
      tester,
    ) async {
      await settings.setDemoMode(true);
      // Short enough that the sidebar and the sample grid overflow it.
      await pumpPhotosRoute(tester, size: const Size(390, 400));
      final scroll = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CustomScrollView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      // Scrolled up to the sidebar, a tap on a row must bring the grid back.
      scroll.position.jumpTo(0);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('album_sidebar_all_photos')));
      await settle(tester);
      expect(scroll.position.pixels, greaterThan(0));

      // A short album may not scroll that far, but its photos are on screen.
      final home = DemoPhotosService.homeAlbumId;
      final homeRow = find.byKey(ValueKey('album_tile_$home'));
      await tester.ensureVisible(homeRow);
      await tester.pump();
      await tester.tap(homeRow);
      await settle(tester);

      expect(tester.takeException(), isNull);
      expect(assetImages(), findsNWidgets(count(home)));
      expect(
        tester.getRect(assetImages().first).top,
        lessThan(400),
        reason: 'the album grid is in view',
      );
    });
  });

  testWidgets('an album link survives an unreachable Quark', (tester) async {
    final router = await pumpPhotosRoute(
      tester,
      location: AppRoutes.photosAlbum('Trips'),
    );

    expect(tester.takeException(), isNull);
    expect(
      router.state.uri.queryParameters[AppRoutes.photosAlbumParam],
      'Trips',
      reason: 'a failed album load must not erase the link',
    );
    expect(find.byType(QuarkDisconnectedView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('renders none of the sample library when off', (tester) async {
    await pumpPhotos(tester);

    expect(tester.takeException(), isNull);
    expect(assetImages(), findsNothing);
    for (final album in DemoPhotosService.albums()) {
      if (album.isSystemAlbum) continue;
      expect(find.text(album.name), findsNothing, reason: album.name);
    }
    expect(
      recorder.requests,
      isNotEmpty,
      reason: 'with demo mode off the page asks the Quark as before',
    );
  });
}

/// Fails every request the way an unreachable Quark does, and remembers that
/// it was asked — the assertion demo mode needs is "nothing was asked".
class _RecordingHttpOverrides extends HttpOverrides {
  final List<Uri> requests = [];

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RecordingHttpClient(requests);
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this.requests);

  final List<Uri> requests;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    requests.add(url);
    return UnreachableQuarkHttpOverrides()
        .createHttpClient(null)
        .openUrl(method, url);
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => openUrl(method, Uri(scheme: 'http', host: host, port: port, path: path));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
