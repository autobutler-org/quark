import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_content.dart';

/// #3364: the info panel showed a photo's location as "48.85660, 2.35220",
/// text that went nowhere when tapped.
void main() {
  const channel = MethodChannel('plugins.flutter.io/url_launcher');
  final launched = <String>[];

  setUp(() {
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'launch') {
            launched.add((call.arguments as Map)['url'] as String);
          }
          return true;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );

  Future<void> pumpContent(WidgetTester tester, PhotoExif exif) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ListView(
              children: MetadataContent.sections(
                context: context,
                name: 'a.jpg',
                metadata: PhotoMetadata(
                  fileName: 'a.jpg',
                  fileSize: 1024,
                  mtime: DateTime(2022, 9, 22),
                  width: 10,
                  height: 10,
                  exif: exif,
                  albums: const [],
                ),
                loading: false,
                onAlbumTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  final openInMaps = find.byKey(const ValueKey('photo_info_open_in_maps'));

  testWidgets('a GPS position opens in maps', (tester) async {
    await pumpContent(
      tester,
      const PhotoExif(latitude: 48.8566, longitude: 2.3522),
    );
    expect(find.text('48.85660, 2.35220'), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);

    await tester.tap(openInMaps);
    await tester.pumpAndSettle();

    final uri = Uri.parse(launched.single);
    expect(uri.host, 'www.google.com');
    expect(uri.queryParameters['query'], '48.8566,2.3522');
  });

  testWidgets('a photo without a position has no maps link', (tester) async {
    await pumpContent(tester, const PhotoExif(make: 'Google'));
    expect(find.text('LOCATION'), findsNothing);
    expect(openInMaps, findsNothing);
  });
}
