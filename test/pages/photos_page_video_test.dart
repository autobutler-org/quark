import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_sort.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/photos_page.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/tap_target_guidelines.dart' show setViewport;

/// #3428: a video listed in Photos is a tile with a video badge, and tapping
/// it plays it from its streaming URL without downloading it as a photo.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping a video plays it and downloads nothing', (tester) async {
    setViewport(tester, const Size(1280, 800));

    final downloads = <String>[];
    final played = <(Uri, String)>[];
    final controller = PhotosController(
      isWeb: true,
      listCache: PhotosListCache(),
      albumsCache: AlbumsCache(),
      activeHost: () => 'https://quark.local',
      getPhotos:
          ({
            int offset = 0,
            int limit = 50,
            String? serial,
            PhotoSortField sort = PhotoSortField.added,
            PhotoSortOrder order = PhotoSortOrder.desc,
            String? q,
          }) async => const wire.PaginatedPhotosResponse(
            photos: [
              wire.PhotoItem(
                relPath: 'camera/clip.mp4',
                fileName: 'clip.mp4',
                size: 1,
                mtime: 0,
                serial: 'sd1',
                isVideo: true,
                duration: Duration(seconds: 42),
              ),
            ],
            total: 1,
            offset: 0,
            limit: 50,
          ),
      listFavoriteKeys: () async => {},
      listAlbums: ({bool tree = false}) async => [],
      downloadFileBytes: (path, {String? serial, String? fileName}) async {
        downloads.add(path);
        return null;
      },
      thumbnailUrl: (path, {String? serial, String? size}) => Uri(
        scheme: DemoPhotosService.assetScheme,
        path: '${DemoPhotosService.assetDir}/aurora.jpg',
      ),
      mediaUrl: (path, {String? serial}) =>
          Uri.parse('https://quark.local/media/$serial/$path'),
      searchFiles: null,
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          home: PhotosPage(
            controller: controller,
            playVideo: (context, url, name) async => played.add((url, name)),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    final tile = find.byKey(const ValueKey('photo_tile_sd1:camera/clip.mp4'));
    expect(tile, findsOneWidget);
    expect(
      find.descendant(of: tile, matching: find.byType(VideoBadge)),
      findsOneWidget,
    );

    await tester.tap(tile);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(played, [
      (Uri.parse('https://quark.local/media/sd1/camera/clip.mp4'), 'clip.mp4'),
    ]);
    expect(find.byType(ImageViewerPage), findsNothing);
    expect(downloads, isEmpty);
  });
}
