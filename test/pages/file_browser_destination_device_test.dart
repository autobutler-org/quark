import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/file_browser_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/secure_storage.dart';

/// #3191: a new folder on the Files page takes the destination an upload
/// would. Each test presses New folder on the real page and reads the
/// `POST /api/v0/files/folder` it sends, if any.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, Object?> device(String name, {String serial = ''}) => {
    'name': name,
    'devicePath': '/dev/$name',
    'mountPoint': '/mnt/$name',
    'isInternal': serial.isEmpty,
    'isEnabled': true,
    if (serial.isNotEmpty) 'usbInfo': {'serial': serial},
  };

  /// Whether the device listing answers; false is a Quark that cannot say.
  late bool devicesListable;
  late List<Uri> created;

  setUpAll(mockSecureStorage);

  setUp(() async {
    devicesListable = true;
    created = [];
    // Before the host is set: the shared client is built once per host and
    // kept (#1782), so it has to come from this factory.
    sharedHttpClientFactory = () => MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/storage/devices/status')) {
        return devicesListable
            ? http.Response(
                jsonEncode({
                  'devices': [
                    device('Built-in'),
                    device('Stick', serial: 'USB1'),
                  ],
                }),
                200,
              )
            : http.Response('{}', 500);
      }
      if (request.method == 'POST' && path.contains('/files/folder')) {
        created.add(request.url);
        return http.Response('{}', 200);
      }
      return http.Response(path.endsWith('/health') ? '{}' : '[]', 200);
    });
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.load();
    await AppSettings.instance.addHost(
      HostEntry(name: 'Test', hostAddress: 'http://localhost:8080'),
    );
    StorageService.invalidateDeviceCache();
  });

  tearDown(() {
    StorageService.invalidateDeviceCache();
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: FileBrowserPage()));
    await tester.pumpAndSettle();
  }

  Future<void> nameNewFolder(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('file_top_bar_new_folder')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(EditableText).last, 'Trip');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
  }

  /// Lets the page's delayed follow-up refresh run so no timer is pending.
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 4));

  testWidgets('a view filtered to one drive creates the folder there', (
    tester,
  ) async {
    await pumpPage(tester);
    // Both drives start selected; deselecting built-in leaves the stick.
    await tester.tap(
      find.byKey(const ValueKey('file_top_bar_device_/dev/Built-in')),
    );
    await tester.pumpAndSettle();
    await nameNewFolder(tester);

    expect(find.text('Upload to device'), findsNothing);
    expect(created.single.queryParameters, {'serial': 'USB1'});
    await drain(tester);
  });

  testWidgets('a view of every drive asks which one', (tester) async {
    await pumpPage(tester);
    await nameNewFolder(tester);

    expect(find.text('Upload to device'), findsOneWidget);
    expect(created, isEmpty);

    await tester.tap(find.byKey(const ValueKey('upload_target_1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('upload_target_confirm')));
    await tester.pumpAndSettle();

    expect(created.single.queryParameters, {'serial': 'USB1'});
    await drain(tester);
  });

  testWidgets('no folder is created when the drives cannot be listed', (
    tester,
  ) async {
    await pumpPage(tester);
    devicesListable = false;
    await nameNewFolder(tester);

    expect(created, isEmpty);
    expect(
      find.text(Errors.message(ApiException(500, ''), 'create the folder')),
      findsOneWidget,
    );
    await drain(tester);
  });
}
