import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Share on a file or folder in Files (#1911): the menu action opens the
/// share sheet for that item, on the device it is on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final requests = <http.Request>[];

  setUp(() {
    requests.clear();
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add(request);
      final Object body = request.url.path == '/api/v0/access/principals'
          ? {'users': <Object>[], 'groups': <Object>[]}
          : {
              'deviceSerial': 'usb1',
              'relPath': 'Docs/Family',
              'canManage': true,
              'canGrantOwner': true,
              'grants': <Object>[],
            };
      return http.Response(jsonEncode(body), 200);
    });
  });

  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  testWidgets('Share opens the sheet for that item on its device', (
    tester,
  ) async {
    const folder = FileNode(
      name: 'Family/',
      size: 0,
      isDir: true,
      deviceName: 'USB',
      devicePath: '',
      deviceSerial: 'usb1',
      dirPath: 'Docs/Family',
    );
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: QuarkTheme.from(QuarkTokens.dark, Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => const FileBrowserController().handleFileAction(
                node: folder,
                action: FileMenuAction.share,
                context: context,
              ),
              child: const Text('share'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('share'));
    await tester.pumpAndSettle();

    expect(find.byType(ShareSheet), findsOneWidget);
    expect(find.text('Share Family'), findsOneWidget);
    final load = requests.firstWhere((r) => r.url.path == '/api/v0/access');
    expect(load.url.queryParameters, {
      'serial': 'usb1',
      'relPath': 'Docs/Family',
    });
  });

  test('a failed share has its own message', () {
    expect(
      const FileBrowserController().failureMessage(FileMenuAction.share),
      'Sharing failed',
    );
  });
}
