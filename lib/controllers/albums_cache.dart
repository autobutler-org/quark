import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';

/// The album tree and the items of every album opened since the app started,
/// so the Photos sidebar and an album opened a second time are there on the
/// first frame while a refresh runs (#1779).
///
/// Sibling to [PhotosListCache], and kept for the same Quark and account: once
/// either changes, what was kept is forgotten, so one Quark's albums never
/// show for another. An album's items are kept with the sort they arrived in
/// and shown only under that sort.
///
/// `AlbumService` drops what its own calls make wrong: the tree when an album
/// is created, renamed, moved or deleted, and an album's items when a photo
/// joins or leaves it.
///
/// ```dart
/// final tree = AlbumsCache.instance.albums;
/// final items = AlbumsCache.instance.items(id, sort: sort, order: order);
/// AlbumsCache.instance.putItems(id, fresh, sort: sort, order: order);
/// ```
class AlbumsCache {
  /// [scope] defaults to the active Quark and account; a test passes its own.
  AlbumsCache({String Function()? scope}) : _scope = scope ?? _activeScope;

  /// The cache every Photos page and `AlbumService` share.
  static final instance = AlbumsCache();

  final String Function() _scope;

  /// The [scope] everything below was kept for.
  String? _keptFor;
  List<PhotoAlbum>? _albums;

  // ponytail: no cap, an entry per album opened this session and each no
  // bigger than the list the page already held; evict the oldest if a
  // library of huge albums ever shows up in a heap profile.
  final Map<
    int,
    ({PhotoSortField sort, PhotoSortOrder order, List<PhotoAlbumItem> items})
  >
  _items = {};

  static String _activeScope() => PhotosListCache.instance.scope;

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

  /// The album tree last kept, or null when there is none.
  List<PhotoAlbum>? get albums {
    _enterScope();
    return _albums;
  }

  /// Keeps the tree [albums] in place of the one kept before.
  void putAlbums(List<PhotoAlbum> albums) {
    _enterScope();
    _albums = List.unmodifiable(albums);
  }

  /// The items of [albumId] last kept in this [sort] and [order], or null
  /// when there are none.
  List<PhotoAlbumItem>? items(
    int albumId, {
    required PhotoSortField sort,
    required PhotoSortOrder order,
  }) {
    _enterScope();
    final kept = _items[albumId];
    return kept != null && kept.sort == sort && kept.order == order
        ? kept.items
        : null;
  }

  /// Keeps [items], which arrived in [sort] and [order], as the items of
  /// [albumId], in place of what was kept for it before.
  void putItems(
    int albumId,
    List<PhotoAlbumItem> items, {
    required PhotoSortField sort,
    required PhotoSortOrder order,
  }) {
    _enterScope();
    _items[albumId] = (
      sort: sort,
      order: order,
      items: List.unmodifiable(items),
    );
  }

  /// Forgets the album tree, and leaves every album's items.
  void dropAlbums() => _albums = null;

  /// Forgets the items of [albumId], or of every album when it is null.
  void dropItems([int? albumId]) =>
      albumId == null ? _items.clear() : _items.remove(albumId);

  /// Forgets everything.
  void clear() {
    _keptFor = null;
    _albums = null;
    _items.clear();
  }
}
