import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/paginated_photos_response.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';

import '../support/reconnecting_events.dart';

/// #3094: the Photos page listened to both `reconnects` and `resync`, so one
/// reconnect refreshed it twice.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a reconnect refreshes the Photos page exactly once', (
    tester,
  ) async {
    var loads = 0;
    final controller = PhotosController(
      // An empty library, so no thumbnail is fetched while the clock waits.
      getPhotos:
          ({
            int offset = 0,
            int limit = 0,
            String? serial,
            sort = PhotoSortField.added,
            order = PhotoSortOrder.desc,
          }) async => PaginatedPhotosResponse(
            photos: const [],
            total: 0,
            offset: 0,
            limit: 0,
          ),
      activeHost: () => 'quark.local',
      // One call per refresh, whatever the list cache answers.
      listFavoriteKeys: () async {
        loads++;
        return <String>{};
      },
      loadDeviceAssets: () async => [],
    );
    final events = ReconnectingEvents();
    await events.start();
    await tester.pumpWidget(
      MaterialApp(home: PhotosPage(controller: controller)),
    );
    await tester.pump(const Duration(seconds: 2));
    final before = loads;
    // The refresh debounce reads the wall clock, which the test clock does
    // not move.
    Future<void> outwaitDebounce() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await outwaitDebounce();
    expect(before, greaterThan(0));

    await events.reconnect(tester);
    await tester.pump(const Duration(seconds: 2));
    await outwaitDebounce();
    await tester.pump(const Duration(seconds: 2));

    // A second refresh would be the one the debounce owes.
    expect(loads, before + 1);
    await events.stop();
  });
}
