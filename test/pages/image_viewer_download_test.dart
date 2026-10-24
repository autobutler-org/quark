import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #3728: Download in the photo viewer says it downloaded, as the PDF and
/// generic viewers do (#3160).
void main() {
  // 64x64 solid PNG: the viewer needs real bytes to decode.
  final bytes = Uint8List.fromList(
    base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
      'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
      'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
      'gg==',
    ),
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    resetSharedHttpClient();
    sharedHttpClientFactory = () =>
        MockClient((_) async => http.Response('{}', 200));
  });

  tearDown(() {
    saveViewedFile = FilesService.saveFile;
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  testWidgets('Download reports the saved photo', (tester) async {
    final saves = <(String, String?, String?)>[];
    saveViewedFile = (path, {serial, fileName}) async {
      saves.add((path, serial, fileName));
      return '/home/me/$fileName';
    };
    setViewport(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerPage(
          bytes: bytes,
          name: 'beach.jpg',
          relPath: 'Trip/beach.jpg',
          serial: 'USB1',
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(QuarkIcons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();

    expect(saves, [('Trip/beach.jpg', 'USB1', 'beach.jpg')]);
    expect(find.text('Downloaded beach.jpg'), findsOneWidget);
  });
}
