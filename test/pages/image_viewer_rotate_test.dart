import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/services/thumbnail_cache_manager.dart';
import 'package:quark/widgets/image_viewer/current_photo.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// A cache manager with nothing on disk to drop.
class _EmptyCacheManager extends Fake implements BaseCacheManager {
  @override
  Future<void> removeFile(String key) async {}
}

/// #1014: rotating asks the Quark to rewrite the file's orientation, then
/// shows the turned bytes upright; the viewer keeps no rotation of its own.
void main() {
  // 64x64 solid PNG — the photo needs a real box to lay out.
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAIAAAAlC+aJAAAAT0lEQVR42u3P'
    'QQkAAAgEsIttCIMZywi+hcEKLNXzWgQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE'
    'BAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQELgvWNcGlSbHPawAAAABJRU5ErkJg'
    'gg==',
  );

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    resetSharedHttpClient();
    sharedHttpClientFactory = buildLocalTrustHttpClient;
  });

  testWidgets('a rotated photo is reloaded and sits upright', (tester) async {
    ThumbnailCacheManager.instance = _EmptyCacheManager();
    final requests = <String>[];
    resetSharedHttpClient();
    sharedHttpClientFactory = () => MockClient((request) async {
      requests.add('${request.method} ${request.url.path}');
      if (request.url.path == '/api/v0/photos/rotate') {
        expect(jsonDecode(request.body)['quarters'], 1);
        return http.Response(jsonEncode({'orientation': 6}), 200);
      }
      return http.Response.bytes(bytes, 200);
    });

    setViewport(tester, const Size(1400, 900));
    await tester.pumpWidget(
      MaterialApp(
        home: ImageViewerPage(
          bytes: Uint8List.fromList(bytes),
          name: 'first.jpg',
          relPath: 'Photos/first.jpg',
          initialIndex: 0,
          imageCount: 1,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(QuarkIcons.rotate_90_degrees_cw_outlined));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(requests, contains('POST /api/v0/photos/rotate'));
    final rotation = tester
        .widget<CurrentPhoto>(find.byType(CurrentPhoto))
        .rotation;
    expect(rotation.value, 0);
  });
}
