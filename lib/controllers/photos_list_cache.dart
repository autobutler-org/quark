import 'package:quark/models/paginated_photos_response.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/photo_grid_config.dart';

/// The Quark photos a visit to the Photos page left behind, and how many the
/// Quark holds in all.
typedef CachedPhotoPage = ({List<PhotoItem> photos, int total});

/// The first page of Quark photos and the favorite keys from the last visit
/// to the Photos page, so the next one has a grid on its first frame while a
/// refresh runs (#1778).
///
/// Sibling to `FileTypeListingCache`, which does this for Docs and Sheets.
/// Everything belongs to the active Quark and account: once either changes,
/// what was kept is forgotten, so one Quark's photos never show for another.
/// Photos are kept with the sort they arrived in and shown only under that
/// sort, and no more than [PhotoGridConfig.maxCachedPhotos] are kept. Device
/// photos come off disk and are not kept at all.
///
/// ```dart
/// final cached = PhotosListCache.instance.photos(sort: sort, order: order);
/// PhotosListCache.instance.putPhotos(
///   page.photos,
///   total: page.total,
///   sort: sort,
///   order: order,
/// );
/// ```
class PhotosListCache {
  /// [scope] defaults to the active Quark and account; a test passes its own.
  PhotosListCache({String Function()? scope}) : _scope = scope ?? _activeScope;

  /// The cache every Photos page shares.
  static final instance = PhotosListCache();

  final String Function() _scope;

  /// The [scope] everything below was kept for.
  String? _keptFor;
  (PhotoSortField, PhotoSortOrder)? _sort;
  CachedPhotoPage? _page;
  Set<String>? _favoriteKeys;

  static String _activeScope() =>
      '$apiBaseUrl\u0000${AppSettings.instance.username ?? ''}';

  /// The Quark and account in use right now. An answer asked for under one
  /// scope must not be kept once this has moved on.
  String get scope => _scope();

  /// Forgets what another Quark or account left.
  void _enterScope() {
    final current = scope;
    if (current == _keptFor) return;
    clear();
    _keptFor = current;
  }

  /// The photos last kept in this [sort] and [order], or null when there are
  /// none.
  CachedPhotoPage? photos({
    required PhotoSortField sort,
    required PhotoSortOrder order,
  }) {
    _enterScope();
    return _sort == (sort, order) ? _page : null;
  }

  /// Keeps the head of [photos], which arrived in [sort] and [order], and the
  /// Quark's [total], in place of what was kept before.
  void putPhotos(
    List<PhotoItem> photos, {
    required int total,
    required PhotoSortField sort,
    required PhotoSortOrder order,
  }) {
    _enterScope();
    _sort = (sort, order);
    _page = (
      photos: List.unmodifiable(photos.take(PhotoGridConfig.maxCachedPhotos)),
      total: total,
    );
  }

  /// The favorite keys last kept, or null when none were ever listed.
  Set<String>? get favoriteKeys {
    _enterScope();
    final keys = _favoriteKeys;
    return keys == null ? null : Set.unmodifiable(keys);
  }

  /// Keeps [keys] in place of the favorites kept before.
  void putFavoriteKeys(Set<String> keys) {
    _enterScope();
    _favoriteKeys = {...keys};
  }

  /// Adds [key] to the favorites kept, or takes it out. Does nothing until a
  /// whole list has been kept: one toggle is not the user's favorites.
  void setFavorite(String key, {required bool isFavorite}) {
    _enterScope();
    final keys = _favoriteKeys;
    if (keys == null) return;
    if (isFavorite) {
      keys.add(key);
    } else {
      keys.remove(key);
    }
  }

  /// Forgets everything.
  void clear() {
    _keptFor = null;
    _sort = null;
    _page = null;
    _favoriteKeys = null;
  }
}
