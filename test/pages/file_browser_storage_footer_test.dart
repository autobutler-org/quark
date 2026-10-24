import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_io_http.dart';
import '../support/secure_storage.dart';

/// Serves an empty folder and a health reading that the test controls, so it
/// can change the disk usage between refreshes and hold a reading in flight.
FakeIoQuark _healthQuark(List<Future<String>> readings) {
  var served = 0;
  return FakeIoQuark(
    (method, url) async => (
      status: 200,
      body: url.path.endsWith('/api/v0/health')
          ? readings[served++]
          : Future.value('[]'),
    ),
  );
}

String _reading(int usedGiB) => jsonEncode({
  'diskPercent': usedGiB,
  'diskUsedBytes': usedGiB << 30,
  'diskTotalBytes': 100 << 30,
});

// The storage footer used to fetch health once, when it was first built, so
// nothing the page did afterward ever changed it (#2151).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockSecureStorage);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
  });

  tearDown(resetSharedHttpClient);

  testWidgets('the refresh button updates the storage footer', (tester) async {
    final second = Completer<String>();
    final quark = _healthQuark([Future.value(_reading(10)), second.future]);

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(const MaterialApp(home: FileBrowserPage()));
      await tester.pumpAndSettle();
      expect(find.textContaining('10.0 GB / 100.0 GB'), findsOneWidget);

      // AutoRefreshMixin drops a refresh within a wall-clock second of the
      // last one, so let real time pass before pressing the button.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 1100)),
      );
      await tester.tap(find.byKey(const ValueKey('refresh_button')));
      await tester.pump();
      expect(
        find.textContaining('10.0 GB / 100.0 GB'),
        findsOneWidget,
        reason: 'the last reading stays up while the refresh is in flight',
      );

      second.complete(_reading(25));
      await tester.pumpAndSettle();
      expect(find.textContaining('25.0 GB / 100.0 GB'), findsOneWidget);
    }, createHttpClient: quark.createHttpClient);
  });

  // Health is far slower than the listing on a real Quark, and waiting on it
  // held up every refresh of the file list (#2189).
  testWidgets('a slow health reading does not hold up the file listing', (
    tester,
  ) async {
    final health = Completer<String>();
    final quark = _healthQuark([health.future]);

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(const MaterialApp(home: FileBrowserPage()));
      await tester.pump();
      await tester.pump();
      expect(quark.requested.map((url) => url.path), contains('/api/v0/files'));
      expect(find.textContaining('10.0 GB / 100.0 GB'), findsNothing);

      health.complete(_reading(10));
      await tester.pumpAndSettle();
      expect(find.textContaining('10.0 GB / 100.0 GB'), findsOneWidget);
    }, createHttpClient: quark.createHttpClient);
  });
}
