import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/models/paginated_photos_response.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/utils/events_config.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/reconnecting_events.dart';

/// #3448, #4270: a conversion job, a restore or a dropped socket sends
/// `upload` and `resync` events in bursts, and the Photos page reloaded once
/// per event that got past the refresh debounce, so an idle grid fetched
/// everything again every second or so for as long as the burst lasted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The page keeps its library sidebar's width in SharedPreferences (#4294).
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a burst of listing events refreshes the Photos page once', (
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
            String? q,
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
    // The refresh debounce reads the wall clock, which the test clock does
    // not move.
    Future<void> outwaitDebounce() => tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1100)),
    );
    await outwaitDebounce();
    final before = loads;
    expect(before, greaterThan(0));

    for (var i = 0; i < 30; i++) {
      final kind = i.isEven ? 'upload' : 'resync';
      events.send(jsonEncode({'kind': kind, 'path': '/photos/$i.jpg'}));
      await tester.pump(const Duration(milliseconds: 100));
      if (i % 10 == 9) await outwaitDebounce();
    }
    await tester.pump(EventsConfig.refreshQuiet);
    await outwaitDebounce();
    await tester.pump(const Duration(seconds: 2));

    expect(loads, before + 1);
    await events.stop();
  });
}
