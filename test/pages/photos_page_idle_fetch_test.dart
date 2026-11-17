import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/paginated_photos_response.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #3365: the Photos grid, left open and idle, asked for the first page of
/// photos, the favorites and the album tree again every few seconds while
/// the Quark was still reading capture dates, and forever when that count
/// stopped going down.
void main() {
  // The test platform is Android, so the page also asks photo_manager for the
  // device library; denying it lets the page settle.
  const photoManager = MethodChannel('com.fluttercandies/photo_manager');
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The page keeps its library sidebar's width in SharedPreferences (#4294).
    SharedPreferences.setMockInitialValues({});
    AppSettings.instance.photoSortField.value = PhotoSortField.taken;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          photoManager,
          (_) async => throw MissingPluginException(),
        );
  });

  tearDown(() {
    AppSettings.instance.photoSortField.value = PhotoSortField.added;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(photoManager, null);
  });

  /// Mounts the Photos page over an empty library whose Quark answers
  /// [pending] for the photos it has still to date, one value per listing
  /// and the last one from then on, and counts what the page asks for while
  /// it sits idle for 10 seconds, less than one auto-refresh interval.
  Future<({int photos, int favorites, int albums})> idle(
    WidgetTester tester,
    List<int> pending,
  ) async {
    var photos = 0, favorites = 0, albums = 0;
    final controller = PhotosController(
      // An empty library, so no thumbnail is fetched while the clock waits.
      getPhotos:
          ({
            int offset = 0,
            int limit = 0,
            String? serial,
            sort = PhotoSortField.added,
            order = PhotoSortOrder.desc,
            String? q,
          }) async {
            final left = pending[photos.clamp(0, pending.length - 1)];
            photos++;
            return PaginatedPhotosResponse(
              photos: const [],
              total: 0,
              offset: 0,
              limit: limit,
              pendingDates: left,
            );
          },
      activeHost: () => 'quark.local',
      listFavoriteKeys: () async {
        favorites++;
        return <String>{};
      },
      listAlbums: ({bool tree = true}) async {
        albums++;
        return [];
      },
      listDevices: () async => [],
      loadDeviceAssets: () async => [],
      searchFiles: null,
    );
    await tester.pumpWidget(
      MaterialApp(home: PhotosPage(controller: controller)),
    );
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    final counts = (photos: photos, favorites: favorites, albums: albums);
    await tester.pumpWidget(const SizedBox());
    return counts;
  }

  testWidgets('an idle library is fetched once', (tester) async {
    final counts = await idle(tester, [0]);

    expect(counts, (photos: 1, favorites: 1, albums: 1));
  });

  testWidgets('while capture dates land, only the photos are asked again', (
    tester,
  ) async {
    final counts = await idle(tester, [3, 2, 1, 0]);

    // One listing per batch of dates read, and none once they are all in.
    expect(counts, (photos: 4, favorites: 1, albums: 1));
  });

  testWidgets('a capture-date count that stops dropping stops the asking', (
    tester,
  ) async {
    final counts = await idle(tester, [5]);

    // One more listing to see that nothing moved; the next refresh asks
    // again rather than a timer every few seconds.
    expect(counts, (photos: 2, favorites: 1, albums: 1));
  });
}
