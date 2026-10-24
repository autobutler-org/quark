import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/file_browser/file_browser_create_fab.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_io_http.dart';
import '../support/secure_storage.dart';
import '../support/tap_target_guidelines.dart' show setViewport;

/// Answers every call with just enough of a backend for the listing to render:
/// a folder of PDFs, long enough to scroll.
FakeIoQuark _listingQuark() =>
    FakeIoQuark((method, url) async => (status: 200, body: _bodyFor(url)));

String _bodyFor(Uri url) {
  if (url.path.endsWith('/api/v0/files/stat')) {
    final path = url.queryParameters['filePath'] ?? '';
    return jsonEncode({
      'isDir': false,
      'fileType': 'pdf',
      'name': path.split('/').last,
    });
  }
  if (url.path.endsWith('/api/v0/files')) {
    return jsonEncode([
      for (var i = 0; i < 40; i++)
        {
          'name': 'file$i.pdf',
          'size': 12,
          'isDir': false,
          'dirPath': '/file$i.pdf',
          'fileType': 'pdf',
        },
    ]);
  }
  return '[]';
}

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

  // The shared client is built once and kept (#1782), so a client built inside
  // one test's HttpOverrides zone would answer the next test's requests too.
  tearDown(resetSharedHttpClient);

  bool fabVisible(WidgetTester tester) => tester
      .widget<FileBrowserCreateFab>(find.byType(FileBrowserCreateFab))
      .visible;

  testWidgets('the create FAB comes back after a pushed viewer pops', (
    tester,
  ) async {
    setViewport(tester, const Size(600, 900));

    await HttpOverrides.runZoned(() async {
      await tester.pumpWidget(
        const MaterialApp(home: FileBrowserPage(initialPath: '/')),
      );
      await tester.pumpAndSettle();

      expect(fabVisible(tester), isTrue, reason: 'FAB starts visible');

      // Scroll the listing down far enough to trip the hide threshold.
      await tester.drag(find.text('file0.pdf'), const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(fabVisible(tester), isFalse, reason: 'scrolling down hides it');

      // A page pushed over the browser, as an archive entry's preview is,
      // never disposes the browser's own State — the flow #1811 is about.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(builder: (_) => const Scaffold()),
        ),
      );
      await tester.pumpAndSettle();
      navigator.pop();
      await tester.pumpAndSettle();

      expect(fabVisible(tester), isTrue, reason: 'back on the list (#1811)');
    }, createHttpClient: _listingQuark().createHttpClient);
  });

  // #1812: Files builds its own Scaffold, so it mirrors by reading the scope
  // itself rather than through QuarkPageScaffold.
  for (final leftHanded in [false, true]) {
    testWidgets('left-handed $leftHanded puts the create FAB and the drawer '
        'on the matching edges', (tester) async {
      const size = Size(360, 640);
      setViewport(tester, size);

      await HttpOverrides.runZoned(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: QuarkHandedness(
              leftHanded: leftHanded,
              child: const FileBrowserPage(initialPath: '/'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final fab = tester.getCenter(find.byType(FileBrowserCreateFab)).dx;
        final brand = tester
            .getCenter(find.byKey(const ValueKey('brand_button')))
            .dx;
        expect(fab < size.width / 2, leftHanded, reason: 'FAB at $fab');
        expect(brand > size.width / 2, leftHanded, reason: 'brand at $brand');

        await tester.tap(find.byKey(const ValueKey('brand_button')));
        await tester.pumpAndSettle();

        final drawer = tester.getRect(find.byType(AppDrawer));
        expect(
          leftHanded ? drawer.right : drawer.left,
          leftHanded ? size.width : 0,
        );
        expect(tester.takeException(), isNull);
      }, createHttpClient: _listingQuark().createHttpClient);
    });
  }
}
