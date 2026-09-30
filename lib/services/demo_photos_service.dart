import 'package:flutter/services.dart';
import 'package:quark/models/paginated_photos_response.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/error_text.dart';

/// The bundled sample library Demo mode shows instead of the Quark's (#1746).
///
/// Every method that stands in for a real service keeps that service's
/// signature, so `PhotosController.demo()` can inject it where the real one
/// would go. None of them makes a network request; album changes are refused
/// with [Errors.demoModeReadOnly].
class DemoPhotosService {
  DemoPhotosService._();

  static const String deviceSerial = 'demo';
  static const String assetDir = 'assets/demo';

  /// The scheme of a thumbnail "url" that names a bundled asset rather than
  /// a place on the network. `PhotoThumbnail` draws these with `Image.asset`.
  static const String assetScheme = 'asset';

  static const int favoritesAlbumId = -1;
  static const int summerTripAlbumId = -2;
  static const int hikingAlbumId = -3;
  static const int homeAlbumId = -4;
  static const int cityBreakAlbumId = -5;

  static bool get isEnabled => AppSettings.instance.demoMode.value;

  static bool isDemoSerial(String? serial) => serial == deviceSerial;

  static final List<PhotoItem> photos = List.unmodifiable([
    _photo('sunrise-hills.jpg', 11215, DateTime.utc(2025, 6, 14, 5, 48)),
    _photo('mountain-lake.jpg', 16181, DateTime.utc(2025, 6, 15, 11, 20)),
    _photo('beach-day.jpg', 15909, DateTime.utc(2025, 7, 2, 14, 5)),
    _photo('city-night.jpg', 50777, DateTime.utc(2025, 7, 19, 22, 41)),
    _photo('forest-fog.jpg', 27697, DateTime.utc(2025, 8, 3, 7, 12)),
    _photo('balloons.jpg', 13344, DateTime.utc(2025, 8, 9, 6, 55)),
    _photo('desert-dunes.jpg', 9431, DateTime.utc(2025, 8, 23, 17, 30)),
    _photo('aurora.jpg', 26979, DateTime.utc(2025, 9, 12, 23, 58)),
    _photo('sailboat.jpg', 18007, DateTime.utc(2025, 9, 20, 18, 14)),
    _photo('lighthouse.jpg', 9639, DateTime.utc(2025, 9, 21, 8, 2)),
    _photo('flower-field.jpg', 33801, DateTime.utc(2025, 10, 4, 12, 26)),
    _photo('coffee.jpg', 20214, DateTime.utc(2025, 10, 11, 9, 15)),
  ]);

  static const List<String> _favoriteFiles = [
    'mountain-lake.jpg',
    'aurora.jpg',
    'sailboat.jpg',
  ];

  /// The hand-picked albums. Favorites is not here: it follows [_favorites].
  static final Map<int, List<String>> _albumFiles = {
    summerTripAlbumId: [
      'beach-day.jpg',
      'sailboat.jpg',
      'lighthouse.jpg',
      'balloons.jpg',
      'sunrise-hills.jpg',
    ],
    hikingAlbumId: [
      'mountain-lake.jpg',
      'forest-fog.jpg',
      'aurora.jpg',
      'desert-dunes.jpg',
    ],
    homeAlbumId: ['coffee.jpg', 'flower-field.jpg'],
    cityBreakAlbumId: ['city-night.jpg'],
  };

  /// Starred sample photos. Local to this run of the app: starring one never
  /// reaches a Quark, and a restart brings back the defaults.
  static final Set<String> _favorites = favoriteKeys();

  // ── Stand-ins for the real services ──────────────────────────────────────

  /// The whole library as one page, so nothing pages further.
  static Future<PaginatedPhotosResponse> getPhotos({
    int offset = 0,
    int limit = 0,
    String? serial,
    PhotoSortField sort = PhotoSortField.added,
    PhotoSortOrder order = PhotoSortOrder.desc,
  }) async {
    final sorted = _sorted(
      photos,
      sort,
      order,
      (p) => p.fileName,
      (p) => p.mtime,
      (p) => p.takenAt ?? p.mtime,
    );
    return PaginatedPhotosResponse(
      photos: sorted,
      total: sorted.length,
      offset: 0,
      limit: sorted.length,
    );
  }

  /// Something non-null, so the controller loads the sample library even
  /// with no Quark configured.
  static String? activeHost() => deviceSerial;

  static Future<Set<String>> listFavoriteKeys() async => {..._favorites};

  static Future<bool> toggleFavorite({
    required String relPath,
    String? serial,
  }) async {
    final key = selectionKey(relPath);
    if (_favorites.remove(key)) return false;
    _favorites.add(key);
    return true;
  }

  static Future<Uint8List?> downloadFileBytes(
    String filePath, {
    String? serial,
    String? fileName,
  }) => loadBytes(filePath);

  static Uri thumbnailUrl(String filePath, {String? serial, String? size}) =>
      Uri(scheme: assetScheme, path: filePath);

  static Future<List<PhotoAlbum>> listAlbums({bool tree = true}) async =>
      albums();

  static Future<PhotoAlbum> createAlbum(String name, {int? parentId}) =>
      _refuse();

  static Future<PhotoAlbum> renameAlbum(int id, String name) => _refuse();

  static Future<void> deleteAlbum(int id) => _refuse();

  static Future<PhotoAlbumItem> addPhotoToAlbum(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  }) => _refuse();

  static Future<void> removePhotoFromAlbum(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  }) => _refuse();

  // ── Catalog ──────────────────────────────────────────────────────────────

  static Future<Uint8List> loadBytes(String relPath) async {
    final data = await rootBundle.load(relPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }

  static String selectionKey(String relPath) => '$deviceSerial:$relPath';

  /// The photos starred out of the box.
  static Set<String> favoriteKeys() => {
    for (final file in _favoriteFiles) selectionKey(_relPath(file)),
  };

  static List<PhotoAlbum> albums() => List.unmodifiable([
    _album(favoritesAlbumId, 'Favorites', smartType: 'favorites'),
    _album(summerTripAlbumId, 'Summer Trip'),
    _album(hikingAlbumId, 'Hiking'),
    _album(homeAlbumId, 'Home'),
    _album(cityBreakAlbumId, 'City Break'),
  ]);

  static List<PhotoAlbumItem> listAlbumItems(
    int albumId, {
    PhotoSortField sort = PhotoSortField.added,
    PhotoSortOrder order = PhotoSortOrder.desc,
  }) {
    final files = _filesIn(albumId);
    final items = [
      for (final (index, file) in files.indexed)
        PhotoAlbumItem(
          id: albumId * 100 - index,
          albumId: albumId,
          deviceSerial: deviceSerial,
          relPath: _relPath(file),
          addedAt: _albumDate,
          takenAt: _takenAt(file),
        ),
    ];
    return List.unmodifiable(
      _sorted(
        items,
        sort,
        order,
        (item) => item.relPath,
        (item) => item.addedAt.millisecondsSinceEpoch ~/ 1000,
        (item) => (item.takenAt ?? item.addedAt).millisecondsSinceEpoch ~/ 1000,
      ),
    );
  }

  /// Orders [items] by [sort]/[order], the same rules the real endpoints
  /// apply server-side, so Demo mode's sort control behaves like a real
  /// Quark's (#2509, #2592).
  static List<T> _sorted<T>(
    List<T> items,
    PhotoSortField sort,
    PhotoSortOrder order,
    String Function(T) name,
    int Function(T) addedTime,
    int Function(T) takenTime,
  ) {
    final ascending = order == PhotoSortOrder.asc;
    final sorted = [...items];
    sorted.sort((a, b) {
      final cmp = switch (sort) {
        PhotoSortField.name => name(
          a,
        ).toLowerCase().compareTo(name(b).toLowerCase()),
        PhotoSortField.added => addedTime(a).compareTo(addedTime(b)),
        PhotoSortField.taken => takenTime(a).compareTo(takenTime(b)),
      };
      return ascending ? cmp : -cmp;
    });
    return sorted;
  }

  static Future<Never> _refuse() async =>
      throw const MessageException(Errors.demoModeReadOnly);

  static final DateTime _albumDate = DateTime.utc(2025, 10, 12, 10, 0);

  static String _relPath(String file) => '$assetDir/$file';

  /// The files in [albumId]. Favorites mirrors the current stars, in catalog
  /// order, the way the Quark's own Favorites album does (#992).
  static List<String> _filesIn(int albumId) => albumId == favoritesAlbumId
      ? [
          for (final photo in photos)
            if (_favorites.contains(selectionKey(photo.relPath)))
              photo.fileName,
        ]
      : _albumFiles[albumId] ?? const [];

  static PhotoItem _photo(String file, int size, DateTime taken) => PhotoItem(
    relPath: _relPath(file),
    fileName: file,
    size: size,
    mtime: taken.millisecondsSinceEpoch ~/ 1000,
    serial: deviceSerial,
    takenAt: taken.millisecondsSinceEpoch ~/ 1000,
  );

  /// When the sample [file] was taken, as its album items report it.
  static DateTime? _takenAt(String file) {
    for (final photo in photos) {
      if (photo.fileName == file && photo.takenAt != null) {
        return DateTime.fromMillisecondsSinceEpoch(
          photo.takenAt! * 1000,
          isUtc: true,
        );
      }
    }
    return null;
  }

  static PhotoAlbum _album(int id, String name, {String? smartType}) =>
      PhotoAlbum(
        id: id,
        name: name,
        smartType: smartType,
        createdAt: _albumDate,
        updatedAt: _albumDate,
        itemCount: _filesIn(id).length,
      );
}
