import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/listing_snapshot_store.dart';
import 'package:quark/widgets/file_browser/folder_route_error_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_io_http.dart';
import '../support/secure_storage.dart';

/// A Quark that answers every request, and a folder listing with [listing].
FakeIoQuark _answering({String listing = '[]'}) => FakeIoQuark(
  (method, url) async => (
    status: 200,
    body: url.path.endsWith('/api/v0/files')
        ? listing
        : url.path.endsWith('/api/v0/access/mine')
        ? '{"items":[]}'
        : url.path.endsWith('/api/v0/storage/devices/status')
        ? '{"devices":[]}'
        : '[]',
  ),
);

/// The disk a cold launch reads: one snapshot, handed over when the test
/// says the read is done.
class _SlowDisk implements ListingSnapshotStore {
  _SlowDisk(this.snapshot);

  /// What the last launch left under `files`.
  final Object? snapshot;

  /// Completing this finishes the read. Synchronous, and never awaited once
  /// complete, because the disk is built in setUp: its future belongs to
  /// the real event loop, which a widget test's fake clock never turns.
  final Completer<void> readDone = Completer<void>.sync();

  /// What has been written since, by name.
  final Map<String, Object?> written = {};

  @override
  Future<Object?> read(String name, {required String scope}) async {
    if (!readDone.isCompleted) await readDone.future;
    return name == 'files' ? snapshot : null;
  }

  @override
  Future<void> write(
    String name,
    Object? data, {
    required String scope,
  }) async => written[name] = data;

  @override
  Future<void> clear() async => written.clear();
}

FileNode _file(String name) => FileNode(
  name: name,
  size: 2048,
  isDir: false,
  deviceName: 'Attic',
  devicePath: '/mnt/attic',
  deviceSerial: 'ATTIC1',
  dirPath: 'users/alice/$name',
);

/// #1781: the Files page shows what the last launch left on disk until the
/// Quark answers, and keeps showing it when the Quark cannot be reached.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(mockSecureStorage);

  // alice is a member, so a bare /files opens her home.
  final landing = homePath('alice');

  late _SlowDisk disk;
  late FileBrowserCache appCache;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    await AppSettings.instance.setUsername('alice');
    AppSettings.instance.isAdmin.value = false;
    // The device list shares one in-flight request, and the listing waits on
    // it: a request left hanging by one test would hold up the next.
    StorageService.invalidateDeviceCache();
    disk = _SlowDisk({
      landing: [_file('last-launch.txt').toJson()],
    });
    appCache = FileBrowserCache.instance;
    FileBrowserCache.instance = FileBrowserCache(
      store: disk,
      account: () => (host: 'http://localhost:8080', username: 'alice'),
      accountChanges: ChangeNotifier(),
    );
  });

  tearDown(() async {
    FileBrowserCache.instance = appCache;
    await AppSettings.instance.setUsername(null);
  });

  // The shared client is built once and kept (#1782), so a client built inside
  // one test's HttpOverrides zone would answer the next test's requests too.
  tearDown(resetSharedHttpClient);

  /// What `main` does before the first frame, and then the page itself.
  Future<void> coldLaunch(WidgetTester tester) async {
    unawaited(FileBrowserCache.instance.hydrate());
    await tester.pumpWidget(const MaterialApp(home: FileBrowserPage()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('a cold launch shows the last listing before the Quark answers', (
    tester,
  ) async {
    // Accepts nothing and refuses nothing: every request stays out.
    final quark = FakeIoQuark((method, url) => Completer<FakeIoReply>().future);

    await HttpOverrides.runZoned(() async {
      await coldLaunch(tester);
      expect(
        find.text('last-launch.txt'),
        findsNothing,
        reason: 'the disk has not been read yet',
      );

      disk.readDone.complete();
      await tester.pump();
      await tester.pump();

      expect(find.text('last-launch.txt'), findsOneWidget);
      expect(find.byType(FolderRouteErrorState), findsNothing);
    }, createHttpClient: quark.createHttpClient);
  });

  testWidgets('an unreachable Quark leaves the last listing on screen', (
    tester,
  ) async {
    // No route to it: every request fails at the socket.
    final quark = FakeIoQuark(
      (method, url) => Future.error(const SocketException('No route to host')),
    );
    disk.readDone.complete();

    await HttpOverrides.runZoned(() async {
      await coldLaunch(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('last-launch.txt'), findsOneWidget);
      expect(find.byType(FolderRouteErrorState), findsNothing);
    }, createHttpClient: quark.createHttpClient);
  });

  testWidgets('the Quark\'s answer replaces the snapshot', (tester) async {
    final quark = _answering(
      listing: jsonEncode([_file('fresh.txt').toJson()]),
    );
    disk.readDone.complete();

    await HttpOverrides.runZoned(() async {
      await coldLaunch(tester);
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('fresh.txt'), findsOneWidget);
      expect(find.text('last-launch.txt'), findsNothing);
      // And it is what the next launch will read.
      expect(jsonEncode(disk.written['files']), contains('fresh.txt'));
    }, createHttpClient: quark.createHttpClient);
  });
}
