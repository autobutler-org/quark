import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:quark/controllers/albums_cache.dart';
import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/controllers/photos_list_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_sort.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/services/dropped_file_reader.dart';
import 'package:quark/services/favorites_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/client_thumbnails.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/album_link.dart' as link;
import 'package:quark/utils/album_order.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/photo_grid_config.dart';
import 'package:quark/utils/photo_month_sections.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/utils/upload_tree_utils.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Which photos the grid shows.
enum PhotoCategory { quark, mobile, all, favorites }

/// A photo loaded for the image viewer: its bytes, its name, and the
/// `relPath` and serial of a Quark-stored photo (both null for a device
/// photo). The shape `ImageViewerPage.onLoadImage` asks for.
typedef LoadedPhoto = (Uint8List?, String, String?, String?);

/// How adding the selection to an album went, so the page can word it.
@immutable
class AddToAlbumOutcome {
  /// Creates an outcome.
  const AddToAlbumOutcome({
    required this.added,
    required this.skipped,
    required this.failed,
    this.error,
  });

  /// Photos the Quark added.
  final int added;

  /// Device photos, which cannot go into an album yet.
  final int skipped;

  /// Photos the Quark refused or never answered for.
  final int failed;

  /// What the last failed photo threw, for the page to word; null when
  /// nothing failed.
  final Object? error;
}

/// Everything the photos page shows and does, kept out of its [State]
/// (#1732).
///
/// Owns the Quark photo pages, the device photos, favorites, the category,
/// the selection, and the album tree, and makes every service call behind
/// them. The page keeps navigation, dialogs, sheets and snack bars, and turns
/// failures into copy.
///
/// Starts out showing the first page and favorites the last visit left in
/// [PhotosListCache], so coming back to Photos draws the grid at once while
/// [refresh] runs; every good refresh and favorite toggle writes back to it
/// (#1778). The album tree, and the items of an album opened before, come
/// out of [AlbumsCache] the same way (#1779).
///
/// A search by file name ([setSearchQuery], #2059) narrows whatever the grid
/// shows. The library's matches come from the Quark's files search, so they
/// reach past the pages loaded so far; an album's items and the device's
/// photos are all on hand and are filtered here.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class PhotosController extends ChangeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  PhotosController({
    Future<wire.PaginatedPhotosResponse> Function({
          int offset,
          int limit,
          String? serial,
          PhotoSortField sort,
          PhotoSortOrder order,
        })
        getPhotos =
        FilesService.getPhotos,
    Future<List<AssetEntity>> Function() loadDeviceAssets =
        PhotosController.deviceAssets,
    String? Function() activeHost = PhotosController._appActiveHost,
    Future<Set<String>> Function() listFavoriteKeys =
        FavoritesService.listFavoriteKeys,
    Future<bool> Function({required String relPath, String? serial})
        toggleFavorite =
        FavoritesService.toggle,
    Future<Uint8List?> Function(
          String filePath, {
          String? serial,
          String? fileName,
        })
        downloadFileBytes =
        FilesService.downloadFileBytes,
    Uri Function(String filePath, {String? serial, String? size}) thumbnailUrl =
        FilesService.constructThumbnailUrl,
    Future<List<PhotoAlbum>> Function({bool tree}) listAlbums =
        AlbumService.listAlbums,
    Future<PhotoAlbum> Function(String name, {int? parentId}) createAlbum =
        AlbumService.createAlbum,
    Future<PhotoAlbum> Function(int id, String name) renameAlbum =
        AlbumService.renameAlbum,
    Future<void> Function(int id) deleteAlbum = AlbumService.deleteAlbum,
    Future<PhotoAlbumItem> Function(
          int albumId, {
          required String deviceSerial,
          required String relPath,
        })
        addPhotoToAlbum =
        AlbumService.addPhotoToAlbum,
    Future<void> Function(
          int albumId, {
          required String deviceSerial,
          required String relPath,
        })
        removePhotoFromAlbum =
        AlbumService.removePhotoFromAlbum,
    Future<List<PhotoAlbumItem>> Function(
          int albumId, {
          PhotoSortField sort,
          PhotoSortOrder order,
        })
        listAlbumItems =
        AlbumService.listAlbumItems,
    Future<List<StorageDevice>> Function() listDevices =
        StorageService.listDevices,
    Future<List<String>> Function(
          String uploadPath,
          List<http.MultipartFile> files, {
          String? serial,
          bool overwrite,
          bool keepBoth,
        })
        uploadFiles =
        FilesService.uploadFilesFromFormData,
    Future<Uint8List?> Function(DropItemFile file) readDroppedFile =
        readDroppedFileBytes,
    Future<Uint8List?> Function(String name, Uint8List bytes) renderFromBytes =
        renderThumbnailFromBytes,
    Future<Uint8List?> Function(DropItemFile file) renderDroppedFile =
        renderDroppedFileThumbnail,
    Future<Uint8List?> Function(String name, String path) renderFromPath =
        renderThumbnailFromPath,
    Future<String?> Function(
          String filePath, {
          String? serial,
          String? fileName,
        })
        saveFile =
        FilesService.saveFile,
    Future<String> Function(String relPath, {String? serial}) copyPhoto =
        FilesService.copyPhoto,
    Future<void> Function(
          String rootDir,
          String fileName, {
          String? deviceSerial,
        })
        deleteFile =
        FilesService.deleteFile,
    Future<List<FileNode>> Function(String query, {List<String>? serials})?
        searchFiles =
        FilesService.searchFiles,
    Duration searchDelay = searchDebounce,
    PhotoBytesCache? bytesCache,
    PhotosListCache? listCache,
    AlbumsCache? albumsCache,
    bool isWeb = kIsWeb,
  }) : _getPhotos = getPhotos,
       _loadDeviceAssets = loadDeviceAssets,
       _activeHost = activeHost,
       _listFavoriteKeys = listFavoriteKeys,
       _toggleFavorite = toggleFavorite,
       _downloadFileBytes = downloadFileBytes,
       _thumbnailUrl = thumbnailUrl,
       _listAlbums = listAlbums,
       _createAlbum = createAlbum,
       _renameAlbum = renameAlbum,
       _deleteAlbum = deleteAlbum,
       _addPhotoToAlbum = addPhotoToAlbum,
       _removePhotoFromAlbum = removePhotoFromAlbum,
       _listAlbumItems = listAlbumItems,
       _listDevices = listDevices,
       _uploadFiles = uploadFiles,
       _readDroppedFile = readDroppedFile,
       _renderFromBytes = renderFromBytes,
       _renderDroppedFile = renderDroppedFile,
       _renderFromPath = renderFromPath,
       _saveFile = saveFile,
       _copyPhoto = copyPhoto,
       _deleteFile = deleteFile,
       _searchFiles = searchFiles,
       _searchDelay = searchDelay,
       _bytesCache = bytesCache ?? PhotoBytesCache.instance,
       _listCache = listCache ?? PhotosListCache.instance,
       _albumsCache = albumsCache ?? AlbumsCache.instance,
       _isWeb = isWeb {
    // With no host there is a different page to show, not an old grid.
    if (_activeHost() == null) return;
    final albums = _albumsCache.albums;
    if (albums != null) {
      _albums = albums;
      _albumsLoading = false;
    }
    _favoriteKeys.addAll(_listCache.favoriteKeys ?? const {});
    final cached = _listCache.photos(sort: _sortField, order: _sortOrder);
    if (cached == null) return;
    _quark = cached.photos.map(_Photo.fromWire).toList(growable: false);
    _quarkSort = (_sortField, _sortOrder);
    _quarkTotal = cached.total;
    _quarkLoaded = true;
  }

  /// A controller over Demo mode's bundled sample library (#1746).
  ///
  /// Every Quark-bound photo and album call is swapped for its
  /// [DemoPhotosService] stand-in, and the Quark's search is left out, so
  /// nothing it shows comes from, or is asked of, a Quark. Device photos and uploads are left as they are. The
  /// samples get caches of their own, so they never show for the Quark.
  factory PhotosController.demo() => PhotosController(
    listCache: PhotosListCache(),
    albumsCache: AlbumsCache(),
    getPhotos: DemoPhotosService.getPhotos,
    activeHost: DemoPhotosService.activeHost,
    listFavoriteKeys: DemoPhotosService.listFavoriteKeys,
    toggleFavorite: DemoPhotosService.toggleFavorite,
    downloadFileBytes: DemoPhotosService.downloadFileBytes,
    thumbnailUrl: DemoPhotosService.thumbnailUrl,
    listAlbums: DemoPhotosService.listAlbums,
    createAlbum: DemoPhotosService.createAlbum,
    renameAlbum: DemoPhotosService.renameAlbum,
    deleteAlbum: DemoPhotosService.deleteAlbum,
    addPhotoToAlbum: DemoPhotosService.addPhotoToAlbum,
    removePhotoFromAlbum: DemoPhotosService.removePhotoFromAlbum,
    listAlbumItems:
        (
          id, {
          sort = PhotoSortField.taken,
          order = PhotoSortOrder.desc,
        }) async =>
            DemoPhotosService.listAlbumItems(id, sort: sort, order: order),
    // The samples all arrive in the first page, so a search filters those.
    searchFiles: null,
  );

  /// How many Quark photos one page fetches.
  static const int pageSize = 50;

  /// How many device photos the first (and only) page fetches.
  static const int deviceAssetPageSize = 200;

  /// How long typing has to pause before the Quark is asked to search.
  static const Duration searchDebounce = Duration(milliseconds: 300);

  final Future<wire.PaginatedPhotosResponse> Function({
    int offset,
    int limit,
    String? serial,
    PhotoSortField sort,
    PhotoSortOrder order,
  })
  _getPhotos;
  final Future<List<AssetEntity>> Function() _loadDeviceAssets;
  final String? Function() _activeHost;
  final Future<Set<String>> Function() _listFavoriteKeys;
  final Future<bool> Function({required String relPath, String? serial})
  _toggleFavorite;
  final Future<Uint8List?> Function(
    String filePath, {
    String? serial,
    String? fileName,
  })
  _downloadFileBytes;
  final Uri Function(String filePath, {String? serial, String? size})
  _thumbnailUrl;
  final Future<List<PhotoAlbum>> Function({bool tree}) _listAlbums;
  final Future<PhotoAlbum> Function(String name, {int? parentId}) _createAlbum;
  final Future<PhotoAlbum> Function(int id, String name) _renameAlbum;
  final Future<void> Function(int id) _deleteAlbum;
  final Future<PhotoAlbumItem> Function(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  })
  _addPhotoToAlbum;
  final Future<void> Function(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  })
  _removePhotoFromAlbum;
  final Future<List<PhotoAlbumItem>> Function(
    int albumId, {
    PhotoSortField sort,
    PhotoSortOrder order,
  })
  _listAlbumItems;
  final Future<List<StorageDevice>> Function() _listDevices;
  final Future<List<String>> Function(
    String uploadPath,
    List<http.MultipartFile> files, {
    String? serial,
    bool overwrite,
    bool keepBoth,
  })
  _uploadFiles;
  final Future<Uint8List?> Function(DropItemFile file) _readDroppedFile;
  final Future<Uint8List?> Function(String name, Uint8List bytes)
  _renderFromBytes;
  final Future<Uint8List?> Function(DropItemFile file) _renderDroppedFile;
  final Future<Uint8List?> Function(String name, String path) _renderFromPath;
  final Future<String?> Function(
    String filePath, {
    String? serial,
    String? fileName,
  })
  _saveFile;
  final Future<String> Function(String relPath, {String? serial}) _copyPhoto;
  final Future<void> Function(
    String rootDir,
    String fileName, {
    String? deviceSerial,
  })
  _deleteFile;

  /// The Quark's file name search, or null to search only what is loaded.
  final Future<List<FileNode>> Function(String query, {List<String>? serials})?
  _searchFiles;
  final Duration _searchDelay;
  final PhotoBytesCache _bytesCache;
  final PhotosListCache _listCache;
  final AlbumsCache _albumsCache;
  final bool _isWeb;

  // ── Photos ─────────────────────────────────────────────────────────────────

  List<_Photo> _quark = const [];

  /// The sort [_quark] arrived in, which a failed refresh into another sort
  /// must not leave on screen under the new one's name.
  (PhotoSortField, PhotoSortOrder)? _quarkSort;
  int _quarkTotal = 0;
  bool _quarkLoaded = false;
  bool _isLoadingMore = false;
  List<_Photo> _mobile = const [];
  bool _noHostSelected = false;
  bool _quarkUnreachable = false;
  final Set<String> _favoriteKeys = {};

  /// Bumped by every [refresh], so a page of photos requested before it
  /// cannot land on top of the list it replaced.
  int _generation = 0;
  bool _disposed = false;

  // ── View choices ───────────────────────────────────────────────────────────

  PhotoCategory _category = PhotoCategory.quark;
  bool _categoriesExpanded = false;
  int _columns = PhotoGridConfig.defaultColumns;
  bool _isUploading = false;

  /// How the grid orders photos, loaded from the persisted setting so it
  /// survives navigation and restart (#2509).
  PhotoSortField _sortField = AppSettings.instance.photoSortField.value;
  PhotoSortOrder _sortOrder = AppSettings.instance.photoSortOrder.value;

  /// How the sidebar orders the user's albums, persisted like the grid sort
  /// (#2510).
  AlbumSort _albumSort = AppSettings.instance.albumSort.value;

  // ── Selection ──────────────────────────────────────────────────────────────

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  AlbumItem? _addingToAlbum;

  // ── Albums ─────────────────────────────────────────────────────────────────

  List<PhotoAlbum> _albums = const [];
  bool _albumsLoading = true;

  /// Whether [_albums] is this visit's own answer from the Quark, not the
  /// tree the last visit left in [_albumsCache].
  bool _albumsFetched = false;
  final Set<int> _expandedAlbumIds = {};

  /// The album the grid was asked to show, or null for the library.
  int? _albumId;

  /// An `?album=` value waiting for the tree's first successful load to be
  /// resolved into [_albumId]. Null once resolved, and for the library. A
  /// failed load keeps it, so an unreachable Quark never erases a shared link.
  String? _pendingLink;

  /// The items of [_albumId], null until they arrive or when they failed.
  List<_Photo>? _albumItems;

  /// The sort [_albumItems] arrived in.
  (PhotoSortField, PhotoSortOrder)? _albumItemsSort;
  Object? _albumError;

  /// Bumped by every album items request, so a slow answer for an album the
  /// user has already left cannot land on the one they moved to.
  int _albumRequest = 0;

  // ── Search ─────────────────────────────────────────────────────────────────

  /// What the grid is narrowed to, trimmed; empty shows everything.
  String _query = '';

  /// The Quark's matches for a query, in the grid's sort. They outlive a
  /// change of query until the new answer lands, narrowed here meanwhile, so
  /// typing never blanks the grid. Null when no search has answered.
  ({String query, List<_Photo> photos})? _searchResults;
  Object? _searchError;
  bool _searchPending = false;
  Timer? _searchTimer;

  /// Bumped by every search and every change of query, so an answer for
  /// text the user has typed past cannot land.
  int _searchRequest = 0;

  /// The photos the grid shows for [selectedCategory], in the package's
  /// terms.
  List<PhotoItem> get photos => [
    for (final photo in _visible())
      PhotoItem(
        id: photo.id,
        name: photo.name,
        isRemote: photo.isRemote,
        hasLiveVideo: photo.hasLiveVideo,
        isFavorite: _favoriteKeys.contains(photo.id),
      ),
  ];

  /// The month runs [photos] is split into under a date sort, headed by the
  /// date that sort orders by (#2592), or null under a name sort, where a
  /// month header would split nothing meaningful (#979).
  List<PhotoGridSection>? get photoSections => switch (_sortField) {
    PhotoSortField.name => null,
    PhotoSortField.added => photoMonthSections([
      for (final photo in _visible()) photo.date,
    ]),
    PhotoSortField.taken => photoMonthSections([
      for (final photo in _visible()) photo.takenDate ?? photo.date,
    ]),
  };

  /// How many photos the grid shows.
  int get photoCount => _visible().length;

  /// Which photos the grid shows.
  PhotoCategory get selectedCategory => _category;

  /// Whether the category picker has anything to pick between. The web
  /// cannot see device photos, so it shows Quark photos only. The categories
  /// filter the library, so they hide while an album shows and come back,
  /// still on the category that was picked, with All photos.
  bool get showsCategories => !_isWeb && !_showsAlbum;

  /// Every category with its count, for the category picker.
  List<PhotoCategoryEntry> get categories {
    // The server's total covers pages not fetched yet; until it is known,
    // count what has arrived.
    final quarkCount = _quarkLoaded ? _quarkTotal : _quark.length;
    return [
      PhotoCategoryEntry(
        id: PhotoCategory.all.name,
        label: 'All',
        count: quarkCount + _mobile.length,
        icon: QuarkIcons.photo_library,
      ),
      PhotoCategoryEntry(
        id: PhotoCategory.quark.name,
        label: 'Quark',
        count: quarkCount,
        icon: QuarkIcons.cloud,
      ),
      PhotoCategoryEntry(
        id: PhotoCategory.mobile.name,
        label: 'Mobile',
        count: _mobile.length,
        icon: QuarkIcons.smartphone,
      ),
      PhotoCategoryEntry(
        id: PhotoCategory.favorites.name,
        label: 'Favorites',
        count: _favoriteKeys.length,
        icon: QuarkIcons.star_rounded,
      ),
    ];
  }

  /// Whether the category picker is expanded.
  bool get categoriesExpanded => _categoriesExpanded;

  /// The grid density the user chose, before it is clamped to the width.
  int get columns => _columns;

  /// The field the grid orders photos by.
  PhotoSortField get sortField => _sortField;

  /// The direction [sortField] orders in.
  PhotoSortOrder get sortOrder => _sortOrder;

  /// The file name search the grid is narrowed to, or empty for none.
  String get searchQuery => _query;

  /// Whether the grid is waiting on the Quark to answer for [searchQuery].
  bool get isSearching => _searchPending && _showsQuarkMatches;

  /// What kept the Quark from answering for [searchQuery], for the page to
  /// word, or null.
  Object? get searchError => _showsQuarkMatches ? _searchError : null;

  /// Whether the grid shows the Quark's answer to a search. An album and the
  /// device's photos are filtered here, so neither waits on it nor fails
  /// with it.
  bool get _showsQuarkMatches =>
      !_showsAlbum && (_isWeb || _category != PhotoCategory.mobile);

  /// Whether another page of Quark photos exists and the grid shows them. A
  /// search's matches arrive whole, so it never has one.
  bool get hasMore =>
      _query.isEmpty &&
      !_showsAlbum &&
      _quarkLoaded &&
      _quark.length < _quarkTotal &&
      (_category == PhotoCategory.quark || _category == PhotoCategory.all);

  /// Whether the next page of Quark photos is in flight.
  bool get isLoadingMore => _isLoadingMore;

  /// Whether the last attempt to list Quark photos never reached the Quark.
  ///
  /// Without this the page would render "No photos yet", telling the user
  /// their library is empty when it is simply out of reach (#1637).
  /// While an album is showing, it is whether its items never reached the
  /// Quark.
  bool get quarkUnreachable {
    if (!_showsAlbum) return _quarkUnreachable;
    final error = _albumError;
    return error != null && isQuarkUnreachableError(error);
  }

  /// The Quark the app is pointed at, or null when none is chosen.
  String? get activeHost => _activeHost();

  /// Whether an upload is in flight.
  bool get isUploading => _isUploading;

  /// Whether photos are being selected.
  bool get selectionMode => _selectionMode;

  /// The [PhotoItem.id]s in the selection.
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);

  /// The album the selection is being added to, or null in plain selection.
  AlbumItem? get addingToAlbum => _addingToAlbum;

  /// How the user's albums are ordered in [albums].
  AlbumSort get albumSort => _albumSort;

  /// The album tree in display order: system albums first, favorites leading
  /// them, then the user's in [albumSort] order, sub-albums included.
  List<AlbumItem> get albums {
    final order = albumOrder(_albumSort);
    final system = _albums.where((a) => a.isSystemAlbum).toList()
      ..sort((a, b) {
        if (a.isFavorites) return -1;
        if (b.isFavorites) return 1;
        return 0;
      });
    return [
      for (final album in system) album.toAlbumItem(),
      for (final album
          in _albums.where((a) => !a.isSystemAlbum).toList()..sort(order))
        album.toAlbumItem(childOrder: order),
    ];
  }

  /// Whether there is no album tree to show yet: none has loaded, and the
  /// last visit left none.
  bool get albumsLoading => _albumsLoading;

  /// The ids of every expanded album.
  Set<int> get expandedAlbumIds => Set.unmodifiable(_expandedAlbumIds);

  /// The id of the album the grid shows, or null for All photos.
  int? get selectedAlbumId => _showsAlbum ? _albumId : null;

  /// The album the grid shows, or null for All photos, or while the tree has
  /// yet to load.
  PhotoAlbum? get selectedAlbum {
    final id = selectedAlbumId;
    return id == null ? null : albumById(id);
  }

  /// The showing album's own sub-albums in [albums] order, for the top of
  /// its view (#2591), or none for All photos.
  List<AlbumItem> get subAlbums {
    final id = selectedAlbumId;
    if (id == null) return const [];
    for (final (album, _) in AlbumItem.depthFirst(albums)) {
      if (album.id == id) return album.children;
    }
    return const [];
  }

  /// Whether the showing album's items are on their way.
  bool get albumLoading =>
      _showsAlbum && _albumItems == null && _albumError == null;

  /// Why the showing album's items could not be loaded, or null.
  Object? get albumError => _showsAlbum ? _albumError : null;

  /// The `?album=` value for what the grid shows, or null for All photos:
  /// the value the grid was asked for while it waits for a tree to resolve
  /// against, and the showing album's [albumLink] after. The page writes it
  /// back to the URL, so a link by id or in the wrong case, a rename, and a
  /// deletion all end on the canonical form, while a link the Quark could not
  /// be asked about yet stays as it was.
  String? get albumLink {
    final pending = _pendingLink;
    if (pending != null || _albumsLoading) return pending;
    final id = selectedAlbumId;
    return id == null ? null : albumLinkFor(id);
  }

  /// The `?album=` value naming the album [id].
  String albumLinkFor(int id) => link.albumLink(_albums, id);

  /// An album id nobody can find in a loaded tree falls back to All photos,
  /// so a stale link or a deleted album never strands the grid. A link still
  /// waiting for the first load counts as showing, so the grid waits with it;
  /// once that load has failed it does not, so the grid shows the library's
  /// own unreachable state rather than an album spinner that never ends.
  bool get _showsAlbum => _albumsLoading
      ? _albumId != null || _pendingLink != null
      : _albumId != null && albumById(_albumId!) != null;

  // ── Loading ────────────────────────────────────────────────────────────────

  /// Reloads everything: the first page of Quark photos, the device photos,
  /// the favorites, and the album tree.
  ///
  /// The current lists stay in place until the new ones arrive, so a refresh
  /// never blanks the grid, and Quark photos already showing in this sort
  /// stay when the Quark cannot be asked for new ones (#1778).
  Future<void> refresh() async {
    final generation = ++_generation;
    final noHost = _activeHost() == null;
    // Read before the requests, so an answer for a Quark, account or sort
    // left mid-request is not kept for the one that replaced it.
    final scope = _listCache.scope;
    final sort = _sortField;
    final order = _sortOrder;

    final Future<_QuarkPage?> quark = noHost
        ? Future.value()
        : _firstQuarkPage();
    final mobile = _isWeb ? Future.value(const <_Photo>[]) : _devicePhotos();
    final favorites = noHost
        ? Future<Set<String>?>.value()
        : _listFavoriteKeys().then<Set<String>?>(
            (keys) => keys,
            onError: (Object _) => null,
          );
    final albums = loadAlbums();
    final albumItems = _loadAlbumItems();
    final search = _search();

    final quarkPage = await quark;
    final mobilePhotos = await mobile;
    final favoriteKeys = await favorites;
    await albums;
    await albumItems;
    await search;
    if (generation != _generation || _disposed) return;

    final sameScope = scope == _listCache.scope;
    _noHostSelected = noHost;
    _mobile = _sortDevicePhotos(mobilePhotos);
    if (favoriteKeys != null) {
      _favoriteKeys
        ..clear()
        ..addAll(favoriteKeys);
      if (sameScope) _listCache.putFavoriteKeys(favoriteKeys);
    }
    final error = quarkPage?.error;
    if (quarkPage == null) {
      // No host is a different state with its own UI, so nothing left over
      // from the host that was just removed may outlive it.
      _quark = const [];
      _quarkTotal = 0;
      _quarkLoaded = false;
      _quarkUnreachable = false;
    } else if (error == null || _quark.isEmpty || _quarkSort != (sort, order)) {
      _quark = quarkPage.photos.map(_Photo.fromWire).toList(growable: false);
      _quarkSort = (sort, order);
      _quarkTotal = quarkPage.total;
      _quarkLoaded = true;
      _quarkUnreachable = error != null && isQuarkUnreachableError(error);
      if (error == null && sameScope) {
        _listCache.putPhotos(
          quarkPage.photos,
          total: quarkPage.total,
          sort: sort,
          order: order,
        );
      }
    }
    notifyListeners();
  }

  /// Fetches the next page of Quark photos, if there is one and none is
  /// already in flight.
  Future<void> loadMoreQuarkPhotos() async {
    // Album items and a search's matches arrive in one call; paging is the
    // unfiltered library's alone.
    if (_showsAlbum || _query.isNotEmpty) return;
    if (_isLoadingMore || !_quarkLoaded || _noHostSelected) return;
    if (_quark.length >= _quarkTotal) return;
    final generation = _generation;

    _isLoadingMore = true;
    notifyListeners();
    try {
      final response = await _getPhotos(
        offset: _quark.length,
        limit: pageSize,
        sort: _sortField,
        order: _sortOrder,
      );
      if (generation != _generation || _disposed) return;
      _quark = [..._quark, ...response.photos.map(_Photo.fromWire)];
      _quarkTotal = response.total;
    } catch (e) {
      debugPrint('[photos_controller.dart] Error loading more photos: $e');
    } finally {
      _isLoadingMore = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<_QuarkPage> _firstQuarkPage() async {
    try {
      final response = await _getPhotos(
        offset: 0,
        limit: pageSize,
        sort: _sortField,
        order: _sortOrder,
      );
      return (photos: response.photos, total: response.total, error: null);
    } catch (e) {
      debugPrint('[photos_controller.dart] Error loading photos: $e');
      return (photos: const <wire.PhotoItem>[], total: 0, error: e);
    }
  }

  Future<List<_Photo>> _devicePhotos() async {
    try {
      final assets = await _loadDeviceAssets();
      return assets.map(_Photo.fromAsset).toList(growable: false);
    } catch (e) {
      debugPrint('[photos_controller.dart] Error loading device photos: $e');
      return const [];
    }
  }

  /// Applies [_sortField]/[_sortOrder] to device photos, which never go
  /// through the sorted Quark endpoints (#2509).
  ///
  /// A device photo carries no real filename ([_Photo.fromAsset] uses the
  /// asset id as a placeholder), so [PhotoSortField.name] has nothing
  /// meaningful to sort by and leaves the device's own order in place. Both
  /// date sorts order by the asset's creation time, which is when the device
  /// took or saved it.
  List<_Photo> _sortDevicePhotos(List<_Photo> photos) {
    if (_sortField == PhotoSortField.name) return photos;
    final ascending = _sortOrder == PhotoSortOrder.asc;
    final sorted = [...photos];
    sorted.sort((a, b) {
      final at =
          a.asset?.createDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt =
          b.asset?.createDateTime ?? DateTime.fromMillisecondsSinceEpoch(0);
      final cmp = at.compareTo(bt);
      return ascending ? cmp : -cmp;
    });
    return sorted;
  }

  /// The device's own photos, from its "All" album. Empty anywhere but
  /// Android and iOS, and wherever the user has not granted access.
  static Future<List<AssetEntity>> deviceAssets() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return const [];
    }
    final permission = await PhotoManager.requestPermissionExtend();
    if (!permission.isAuth) return const [];
    final paths = await PhotoManager.getAssetPathList(
      onlyAll: true,
      type: RequestType.image,
    );
    if (paths.isEmpty) return const [];
    return paths.first.getAssetListPaged(page: 0, size: deviceAssetPageSize);
  }

  static String? _appActiveHost() => AppSettings.instance.activeHost;

  List<_Photo> _visible() {
    if (_showsAlbum) return _matching(_albumItems ?? const []);
    final quark = _quarkMatches();
    if (_isWeb) return quark;
    final mobile = _matching(_mobile);
    return switch (_category) {
      PhotoCategory.quark => quark,
      PhotoCategory.mobile => mobile,
      PhotoCategory.all => [...quark, ...mobile],
      PhotoCategory.favorites => [
        for (final photo in [...quark, ...mobile])
          if (_favoriteKeys.contains(photo.id)) photo,
      ],
    };
  }

  /// The [photos] whose name contains [_query], whatever its case.
  List<_Photo> _matching(List<_Photo> photos) {
    if (_query.isEmpty) return photos;
    final query = _query.toLowerCase();
    return [
      for (final photo in photos)
        if (photo.searchName.toLowerCase().contains(query)) photo,
    ];
  }

  /// The Quark photos matching [_query]: the Quark's own answer once it has
  /// one, and until then the matches among the last answer or, with none,
  /// the pages loaded so far.
  List<_Photo> _quarkMatches() {
    final results = _searchResults;
    if (results == null) return _matching(_quark);
    return results.query == _query ? results.photos : _matching(results.photos);
  }

  _Photo? _byId(String id) {
    for (final photo in [
      ..._quark,
      ..._mobile,
      ...?_albumItems,
      ...?_searchResults?.photos,
    ]) {
      if (photo.id == id) return photo;
    }
    return null;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    super.dispose();
  }

  // ── Search ─────────────────────────────────────────────────────────────────

  /// Narrows the grid to photos whose file name contains [text], or shows
  /// everything again when it is blank (#2059).
  ///
  /// What is on hand narrows at once. The library's matches are then asked
  /// of the Quark, once typing has paused for the search delay, so photos on
  /// pages not loaded yet are found too.
  void setSearchQuery(String text) {
    final query = text.trim();
    if (query == _query) return;
    _query = query;
    _searchError = null;
    _searchRequest++;
    _searchTimer?.cancel();
    if (query.isEmpty) _searchResults = null;
    _searchPending =
        query.isNotEmpty && _searchFiles != null && _activeHost() != null;
    if (_searchPending) _searchTimer = Timer(_searchDelay, _search);
    notifyListeners();
  }

  /// Asks the Quark for the photos matching [_query]. The files search
  /// answers with files of every kind, so only the images are kept.
  ///
  /// When it fails, matches already showing for the same query stay, the way
  /// the grid survives a failed [refresh]; with none to keep, [searchError]
  /// says why.
  // ponytail: the files search stops at 500 files of any kind and knows no
  // capture date or live video; a `q` on GET /photos would lift all three.
  Future<void> _search() async {
    final search = _searchFiles;
    final query = _query;
    if (query.isEmpty || search == null || _activeHost() == null) return;
    final request = ++_searchRequest;
    try {
      final files = await search(query);
      if (request != _searchRequest || _disposed) return;
      _searchResults = (
        query: query,
        photos: _sortMatches([
          for (final file in files)
            if (!file.isDir && fileKindForName(file.name) == FileKind.image)
              _Photo.fromFile(file),
        ]),
      );
      _searchError = null;
    } catch (e) {
      debugPrint('[photos_controller.dart] Error searching photos: $e');
      if (request != _searchRequest || _disposed) return;
      if (_searchResults?.query != query) {
        _searchResults = null;
        _searchError = e;
      }
    }
    _searchPending = false;
    notifyListeners();
  }

  /// Puts a search's matches in [_sortField]/[_sortOrder], which the files
  /// search knows nothing of. Both date sorts order by the modified time, the
  /// only date it sends.
  List<_Photo> _sortMatches(List<_Photo> photos) {
    final sign = _sortOrder == PhotoSortOrder.asc ? 1 : -1;
    final epoch = DateTime.fromMillisecondsSinceEpoch(0);
    return [...photos]..sort(
      (a, b) =>
          sign *
          (_sortField == PhotoSortField.name
              ? a.name.toLowerCase().compareTo(b.name.toLowerCase())
              : (a.date ?? epoch).compareTo(b.date ?? epoch)),
    );
  }

  // ── View choices ───────────────────────────────────────────────────────────

  /// Shows [category], and folds the category picker away.
  void selectCategory(PhotoCategory category) {
    _category = category;
    _categoriesExpanded = false;
    notifyListeners();
  }

  /// Expands or folds the category picker.
  void toggleCategoriesExpanded() {
    _categoriesExpanded = !_categoriesExpanded;
    notifyListeners();
  }

  /// Sets the grid density.
  void setColumns(int columns) {
    _columns = columns;
    notifyListeners();
  }

  /// Sets the sort field and order together and reloads every visible list in
  /// the new order (#2509).
  Future<void> setSort(PhotoSortField field, PhotoSortOrder order) async {
    if (field == _sortField && order == _sortOrder) return;
    _sortField = field;
    _sortOrder = order;
    // The refresh below searches again, but may fail and keep these.
    final results = _searchResults;
    if (results != null) {
      _searchResults = (
        query: results.query,
        photos: _sortMatches(results.photos),
      );
    }
    await AppSettings.instance.setPhotoSort(field, order);
    notifyListeners();
    await refresh();
  }

  /// Reorders the sidebar's albums by [sort] and persists the choice. The
  /// albums are already loaded, so nothing is fetched (#2510).
  Future<void> setAlbumSort(AlbumSort sort) async {
    if (sort == _albumSort) return;
    _albumSort = sort;
    notifyListeners();
    await AppSettings.instance.setAlbumSort(sort);
  }

  // ── Favorites ──────────────────────────────────────────────────────────────

  /// Flips whether the Quark photo [id] is a favorite, then reloads the album
  /// tree so the Favorites album's count follows. Device photos cannot be
  /// favorited and are ignored. Throws what the Quark threw.
  Future<void> toggleFavorite(String id) async {
    final photo = _byId(id);
    final relPath = photo?.relPath;
    if (photo == null || relPath == null) return;
    final serial = photo.serial ?? '';
    final isFavorite = await _toggleFavorite(
      relPath: relPath,
      serial: serial.isNotEmpty ? serial : null,
    );
    _listCache.setFavorite(id, isFavorite: isFavorite);
    // The Favorites album is the starred photos, so its kept items are stale.
    for (final album in _albums) {
      if (album.isFavorites) _albumsCache.dropItems(album.id);
    }
    if (isFavorite) {
      _favoriteKeys.add(id);
    } else {
      _favoriteKeys.remove(id);
      // The Favorites album is the starred photos, so un-starring leaves it.
      final items = _albumItems;
      if (items != null && (selectedAlbum?.isFavorites ?? false)) {
        _albumItems = [
          for (final item in items)
            if (item.id != id) item,
        ];
      }
    }
    notifyListeners();
    await loadAlbums();
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  /// Starts selecting photos, with nothing selected. With [addingTo], the
  /// selection is headed for that album, and the grid switches to All photos
  /// to pick from until the selection is added or canceled.
  void enterSelectionMode({AlbumItem? addingTo}) {
    if (addingTo != null) _albumId = null;
    _selectionMode = true;
    _addingToAlbum = addingTo;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Stops selecting photos and forgets the selection. When the selection was
  /// headed for an album, the grid goes back to that album.
  void exitSelectionMode() {
    final returnTo = _addingToAlbum;
    _selectionMode = false;
    _addingToAlbum = null;
    _selectedIds.clear();
    notifyListeners();
    if (returnTo != null) unawaited(showAlbum(returnTo.id));
  }

  /// Adds [id] to the selection, or takes it out.
  void toggleSelection(String id) {
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
    notifyListeners();
  }

  /// Selects every photo the grid shows.
  void selectAll() {
    _selectedIds.addAll(_visible().map((photo) => photo.id));
    notifyListeners();
  }

  /// Clears the selection but keeps selecting.
  void deselectAll() {
    _selectedIds.clear();
    notifyListeners();
  }

  /// What a long press does: starts selecting if nothing is being selected,
  /// then toggles [id].
  void selectFromLongPress(String id) {
    if (!_selectionMode) {
      _selectionMode = true;
      _addingToAlbum = null;
      _selectedIds.clear();
    }
    toggleSelection(id);
  }

  /// Adds every selected Quark photo to [albumId], then leaves selection mode.
  /// When adding to an album added nothing, selection mode stays, so the user
  /// can try again.
  ///
  /// Device photos are counted as skipped, and a photo the Quark refuses as
  /// failed, so the page can say what happened.
  Future<AddToAlbumOutcome> addSelectedToAlbum(int albumId) async {
    var added = 0;
    var skipped = 0;
    var failed = 0;
    Object? error;
    for (final photo in [..._quark, ..._mobile]) {
      if (!_selectedIds.contains(photo.id)) continue;
      final relPath = photo.relPath;
      if (relPath == null) {
        skipped++;
        continue;
      }
      try {
        await _addPhotoToAlbum(
          albumId,
          deviceSerial: photo.serial ?? '',
          relPath: relPath,
        );
        added++;
      } catch (e) {
        failed++;
        error = e;
      }
    }
    if (added > 0 || _addingToAlbum == null) exitSelectionMode();
    return AddToAlbumOutcome(
      added: added,
      skipped: skipped,
      failed: failed,
      error: error,
    );
  }

  // ── Albums ─────────────────────────────────────────────────────────────────

  /// Reloads the album tree, and keeps it for the next visit. A failure
  /// leaves the last tree in place.
  ///
  /// A successful load also resolves an `?album=` value still pending, and
  /// loads that album's items. A failed one leaves the value pending for the
  /// next load, whether a manual refresh, a pull, or a resume.
  Future<void> loadAlbums() async {
    // Read before the request, so a tree from a Quark or account left
    // mid-request is not kept for the one that replaced it.
    final scope = _albumsCache.scope;
    var loaded = false;
    try {
      _albums = await _listAlbums(tree: true);
      loaded = true;
      _albumsFetched = true;
      if (scope == _albumsCache.scope) _albumsCache.putAlbums(_albums);
    } catch (e) {
      debugPrint('[photos_controller.dart] Error loading albums: $e');
    }
    _albumsLoading = false;
    final pending = _pendingLink;
    final showing = !loaded || pending == null
        ? null
        : showAlbum(link.resolveAlbumLink(_albums, pending)?.id);
    notifyListeners();
    await showing;
  }

  /// A fresh copy of the albums a photo can be added to, for a picker that
  /// loads its own. System albums are left out. Throws what the Quark threw.
  Future<List<AlbumItem>> fetchAlbums() async =>
      (await _listAlbums(tree: true)).toUserAlbumItems();

  /// The app album behind [id], searched through the whole tree.
  PhotoAlbum? albumById(int id) {
    PhotoAlbum? search(List<PhotoAlbum> albums) {
      for (final album in albums) {
        if (album.id == id) return album;
        final found = search(album.children);
        if (found != null) return found;
      }
      return null;
    }

    return search(_albums);
  }

  /// Whether an album other than [except] under [parentId] — null for the
  /// top level, where Favorites and Inbox sit too — is already named [name].
  ///
  /// Case is ignored for ASCII letters only, the way the Quark's database
  /// compares names. The tree can be stale, so the Quark's 409 stays the real
  /// guard; this only spares the user a round trip.
  bool albumNameTaken(String name, {int? parentId, int? except}) {
    final siblings = parentId == null
        ? _albums
        : albumById(parentId)?.children ?? const <PhotoAlbum>[];
    final wanted = _foldAscii(name.trim());
    return siblings.any(
      (album) => album.id != except && _foldAscii(album.name) == wanted,
    );
  }

  /// [text] with `A`-`Z` lowered and everything else as it was, like SQLite's
  /// case-insensitive collation.
  static String _foldAscii(String text) => String.fromCharCodes(
    text.codeUnits.map((c) => c >= 0x41 && c <= 0x5A ? c + 0x20 : c),
  );

  /// Shows the album [id] in the grid and loads its items, or goes back to
  /// All photos for null, in whichever category was showing. Items kept from
  /// the last time the album was open show until the load answers. Selection
  /// is a library feature, so showing an album ends it.
  Future<void> showAlbum(int? id) async {
    _pendingLink = null;
    if (id == _albumId) return;
    _albumId = id;
    _albumItems = null;
    _albumError = null;
    final kept = id == null
        ? null
        : _albumsCache.items(id, sort: _sortField, order: _sortOrder);
    if (kept != null) _showAlbumItems(kept, (_sortField, _sortOrder));
    if (id != null) {
      _selectionMode = false;
      _addingToAlbum = null;
      _selectedIds.clear();
    }
    notifyListeners();
    await _loadAlbumItems();
  }

  /// Shows the album an `?album=` [value] names (see
  /// `resolveAlbumLink`), or All photos for null, empty, or a value naming no
  /// album. Before the tree has loaded, or while an earlier value still waits
  /// on a failed load, the value replaces the one waiting. So does a value
  /// the tree kept from the last visit cannot name: the album may be newer
  /// than that tree, so it waits for this visit's.
  Future<void> showAlbumLink(String? value) async {
    final wanted = value == null || value.isEmpty ? null : value;
    if (!_albumsLoading && _pendingLink == null) {
      final album = wanted == null
          ? null
          : link.resolveAlbumLink(_albums, wanted);
      if (wanted == null || album != null || _albumsFetched) {
        await showAlbum(album?.id);
        return;
      }
    }
    if (wanted == _pendingLink && _albumId == null) return;
    _pendingLink = wanted;
    _albumId = null;
    _albumItems = null;
    _albumError = null;
    notifyListeners();
  }

  /// Takes the photo [id] out of the showing album, then reloads the tree so
  /// the album's count follows. Throws what the Quark threw.
  Future<void> removeFromSelectedAlbum(String id) async {
    final albumId = selectedAlbumId;
    final photo = _byId(id);
    final relPath = photo?.relPath;
    if (albumId == null || relPath == null) return;
    await _removePhotoFromAlbum(
      albumId,
      deviceSerial: photo!.serial ?? '',
      relPath: relPath,
    );
    final items = _albumItems;
    if (albumId == _albumId && items != null) {
      _albumItems = [
        for (final item in items)
          if (item.id != id) item,
      ];
      notifyListeners();
    }
    await loadAlbums();
  }

  /// Where the Quark photo [id] is stored, or null for a device photo.
  ({String serial, String relPath})? quarkPathOf(String id) {
    final photo = _byId(id);
    final relPath = photo?.relPath;
    if (relPath == null) return null;
    return (serial: photo!.serial ?? '', relPath: relPath);
  }

  // ── One Quark photo ───────────────────────────────────────────────────────

  /// Downloads the Quark photo [id] to the device (#2276). Does nothing for a
  /// device photo. Throws what the Quark threw.
  Future<void> downloadPhoto(String id) async {
    final path = quarkPathOf(id);
    if (path == null) return;
    await _saveFile(
      path.relPath,
      serial: path.serial.isEmpty ? null : path.serial,
      fileName: _byId(id)!.name,
    );
  }

  /// Copies the Quark photo [id] beside itself and reloads the library, so
  /// the copy shows. Returns the copy's file name, or null for a device
  /// photo. Throws what the Quark threw.
  Future<String?> copyPhoto(String id) async {
    final path = quarkPathOf(id);
    if (path == null) return null;
    final copy = await _copyPhoto(
      path.relPath,
      serial: path.serial.isEmpty ? null : path.serial,
    );
    await refresh();
    return copy.split('/').last;
  }

  /// Moves the Quark photo [id] to the trash and reloads the library. Does
  /// nothing for a device photo. Throws what the Quark threw.
  Future<void> deletePhoto(String id) async {
    final path = quarkPathOf(id);
    if (path == null) return;
    final slash = path.relPath.lastIndexOf('/');
    await _deleteFile(
      slash < 0 ? '' : path.relPath.substring(0, slash),
      path.relPath.substring(slash + 1),
      deviceSerial: path.serial.isEmpty ? null : path.serial,
    );
    // Any album may have held it.
    _albumsCache.dropItems();
    await refresh();
  }

  /// Loads the items of the album being shown, if any, and keeps them for
  /// the next time it is opened. A failure leaves items already showing in
  /// this sort in place; with none to show, it is kept for the page to word.
  Future<void> _loadAlbumItems() async {
    final id = _albumId;
    if (id == null) return;
    final request = ++_albumRequest;
    // Read before the request, so an answer for a Quark, account or sort
    // left mid-request is not kept for the one that replaced it.
    final scope = _albumsCache.scope;
    final sort = (_sortField, _sortOrder);
    try {
      final items = await _listAlbumItems(id, sort: sort.$1, order: sort.$2);
      if (request != _albumRequest || _disposed) return;
      _showAlbumItems(items, sort);
      if (scope == _albumsCache.scope) {
        _albumsCache.putItems(id, items, sort: sort.$1, order: sort.$2);
      }
    } catch (e) {
      if (request != _albumRequest || _disposed) return;
      debugPrint('[photos_controller.dart] Error loading album items: $e');
      if (_albumItems == null || _albumItemsSort != sort) {
        _albumItems = null;
        _albumError = e;
      }
    }
    notifyListeners();
  }

  /// Puts [items], which arrived in [sort], in the grid as the showing
  /// album's.
  void _showAlbumItems(
    List<PhotoAlbumItem> items,
    (PhotoSortField, PhotoSortOrder) sort,
  ) {
    _albumItems = items.map(_Photo.fromAlbumItem).toList(growable: false);
    _albumItemsSort = sort;
    _albumError = null;
  }

  /// Expands the album [id], or folds it.
  void toggleAlbumExpanded(int id) {
    if (!_expandedAlbumIds.remove(id)) _expandedAlbumIds.add(id);
    notifyListeners();
  }

  /// Creates an album named [name], under [parentId] when given, and reloads
  /// the tree. Answers with the album, for a caller that has something to put
  /// in it already (#2041). Throws what the Quark threw.
  Future<AlbumItem> createAlbum(String name, {int? parentId}) async {
    final album = await _createAlbum(name, parentId: parentId);
    await loadAlbums();
    return album.toAlbumItem();
  }

  /// Renames the album [id] and reloads the tree. Throws what the Quark
  /// threw.
  Future<void> renameAlbum(int id, String name) async {
    await _renameAlbum(id, name);
    await loadAlbums();
  }

  /// Deletes the album [id] and reloads the tree. Throws what the Quark
  /// threw.
  Future<void> deleteAlbum(int id) async {
    await _deleteAlbum(id);
    await loadAlbums();
  }

  // ── Uploads ────────────────────────────────────────────────────────────────

  /// The enabled devices an upload can go to. Empty when they cannot be
  /// listed, which uploads to the default device.
  Future<List<UploadTarget>> uploadTargets() async {
    try {
      return [
        for (final device in await _listDevices())
          if (device.isEnabled) device.toUploadTarget(),
      ];
    } catch (e) {
      debugPrint('[photos_controller.dart] Error listing devices: $e');
      return const [];
    }
  }

  /// Uploads [files] to the device with [serial], or the default device when
  /// null. Throws what the upload threw.
  ///
  /// With an [albumId], each uploaded photo is then added to that album
  /// (#2240), and the outcome says how many made it; null without one. A
  /// photo the Quark did not report a path for counts as failed.
  Future<AddToAlbumOutcome?> uploadPhotos(
    List<PlatformFile> files, {
    String? serial,
    int? albumId,
  }) async {
    _isUploading = true;
    notifyListeners();
    try {
      final multipart = <http.MultipartFile>[];
      for (final file in files) {
        final path = file.path;
        if (!_isWeb && path != null && path.isNotEmpty) {
          multipart.add(
            await http.MultipartFile.fromPath(
              'files',
              path,
              filename: file.name,
            ),
          );
          final thumbnail = await _renderQuietly(
            () => _renderFromPath(file.name, path),
          );
          if (thumbnail != null) {
            multipart.add(thumbnailPart(file.name, thumbnail));
          }
          continue;
        }
        final bytes = await file.readAsBytes();
        multipart.add(
          http.MultipartFile.fromBytes('files', bytes, filename: file.name),
        );
        // The thumbnail follows its file: the Quark pairs them by name (#2379).
        final thumbnail = await _renderQuietly(
          () => _renderFromBytes(file.name, bytes),
        );
        if (thumbnail != null) {
          multipart.add(thumbnailPart(file.name, thumbnail));
        }
      }
      final paths = await _uploadToLibrary(multipart, serial: serial);
      if (albumId == null) return null;
      var added = 0;
      Object? error;
      for (final relPath in paths) {
        try {
          await _addPhotoToAlbum(
            albumId,
            deviceSerial: serial ?? '',
            relPath: relPath,
          );
          added++;
        } catch (e) {
          error = e;
        }
      }
      return AddToAlbumOutcome(
        added: added,
        skipped: 0,
        failed: files.length - added,
        error: error,
      );
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Sorts what was dropped onto the page into the photos, walking into
  /// dropped folders, and a count of the files that are not photos (#2214).
  ///
  /// By extension, the same table that decides which files open in the image
  /// viewer. A browser's MIME type for a raw camera file is often empty.
  ({List<PendingUpload> photos, int notPhotos}) sortDroppedFiles(
    List<DropItem> items,
  ) {
    final flattened = flattenDroppedItems(
      items,
      buildUpload: (file, name) async {
        final bytes = await _readDroppedFile(file);
        if (bytes == null || bytes.isEmpty) return null;
        return http.MultipartFile.fromBytes('files', bytes, filename: name);
      },
      renderThumbnail: _renderDroppedFile,
    );
    final photos = [
      for (final upload in flattened.uploads)
        if (fileKindForName(upload.name) == FileKind.image) upload,
    ];
    return (
      photos: photos,
      notPhotos: flattened.uploads.length - photos.length,
    );
  }

  /// Uploads the dropped [photos] to the device with [serial], or the
  /// default device when null, and returns how many went up. One request a
  /// photo, so only one is ever held in memory. Throws what the upload threw.
  Future<int> uploadDroppedPhotos(
    List<PendingUpload> photos, {
    String? serial,
  }) async {
    _isUploading = true;
    notifyListeners();
    try {
      var uploaded = 0;
      for (final photo in photos) {
        final file = await photo.build();
        if (file == null) continue;
        final render = photo.renderThumbnail;
        final thumbnail = render == null ? null : await _renderQuietly(render);
        await _uploadToLibrary([
          file,
          if (thumbnail != null) thumbnailPart(photo.name, thumbnail),
        ], serial: serial);
        uploaded++;
      }
      return uploaded;
    } finally {
      _isUploading = false;
      notifyListeners();
    }
  }

  /// Runs [render], treating a failure as nothing rendered: the photo still
  /// uploads without a client-rendered thumbnail.
  Future<Uint8List?> _renderQuietly(
    Future<Uint8List?> Function() render,
  ) async {
    try {
      return await render();
    } catch (e) {
      debugPrint('[photos_controller.dart] No thumbnail: $e');
      return null;
    }
  }

  /// Uploads [files] to the library root and returns the files-relative path
  /// each one landed at (#2240).
  Future<List<String>> _uploadToLibrary(
    List<http.MultipartFile> files, {
    String? serial,
  }) {
    // Photos come off cameras with names like IMG_0001.jpg, so clashes are
    // routine and the file's name carries nothing the user chose. Rather
    // than the Quark's 409 (#2016), the import asks for both to be kept.
    return _uploadFiles('', files, serial: serial, keepBoth: true);
  }

  // ── Viewer ─────────────────────────────────────────────────────────────────

  /// Where the thumbnail of the Quark photo [id] is served, or null for a
  /// device photo.
  Uri? thumbnailUrl(String id) {
    final photo = _byId(id);
    final relPath = photo?.relPath;
    if (relPath == null) return null;
    return _thumbnailUrl(relPath, serial: photo!.serial);
  }

  /// The path and device of the Quark photo [id], or null for a device
  /// photo, for filling in a thumbnail the Quark lacks (#2381). A sample
  /// photo's thumbnail is a bundled asset and never asks.
  ({String path, String serial})? thumbnailSource(String id) {
    final photo = _byId(id);
    final relPath = photo?.relPath;
    if (relPath == null) return null;
    return (path: relPath, serial: photo!.serial ?? '');
  }

  /// The device asset behind [id], or null for a Quark photo.
  AssetEntity? assetFor(String id) => _byId(id)?.asset;

  /// Downloads the photo at [index] of the grid to open the viewer on, or
  /// null when there are no bytes to show.
  Future<LoadedPhoto?> openPhotoAt(int index) async {
    final photos = _visible();
    if (index < 0 || index >= photos.length) return null;
    final photo = photos[index];
    final relPath = photo.relPath;
    final Uint8List? bytes;
    if (relPath == null) {
      bytes = await photo.asset!.originBytes;
    } else {
      bytes = await _downloadFileBytes(relPath, serial: photo.serial);
    }
    if (bytes == null) return null;
    return (bytes, photo.name, relPath, photo.serial);
  }

  /// Loads the photo at [index] for an open viewer, through the photo cache.
  ///
  /// Failures propagate unchanged so the viewer can offer a retry and the
  /// page can tell a 404 from a dropped request (#1708).
  Future<LoadedPhoto> loadPhotoAt(int index) async {
    final photos = _visible();
    if (index < 0 || index >= photos.length) return (null, '', null, null);
    final photo = photos[index];
    final relPath = photo.relPath;
    if (relPath == null) {
      return (await photo.asset!.originBytes, photo.name, null, null);
    }
    return (await _cachedBytes(photo), photo.name, relPath, photo.serial);
  }

  /// Downloads the photo at [index] into the cache so the viewer's next step
  /// is instant (#1710). Device photos come off disk and are skipped.
  Future<void> prefetchPhotoAt(int index) async {
    final photos = _visible();
    if (index < 0 || index >= photos.length) return;
    final photo = photos[index];
    if (photo.relPath == null) return;
    await _cachedBytes(photo);
  }

  Future<Uint8List?> _cachedBytes(_Photo photo) => _bytesCache.fetch(
    PhotoBytesCache.key(photo.relPath!, photo.serial),
    () => _downloadFileBytes(photo.relPath!, serial: photo.serial),
  );
}

/// The first page of Quark photos, or the [error] that kept it away.
typedef _QuarkPage = ({List<wire.PhotoItem> photos, int total, Object? error});

/// One photo from either source, with what the services need to reach it.
class _Photo {
  const _Photo({
    required this.id,
    required this.name,
    this.relPath,
    this.serial,
    this.asset,
    this.hasLiveVideo = false,
    this.date,
    this.takenDate,
  });

  /// A Quark-stored photo from the paginated photos endpoint.
  factory _Photo.fromWire(wire.PhotoItem photo) {
    final node = FileNode(
      name: photo.fileName,
      size: photo.size,
      isDir: false,
      deviceName: '',
      devicePath: '',
      deviceSerial: photo.serial,
      dirPath: photo.relPath,
    );
    return _Photo(
      id: '${node.deviceSerial}:${node.apiPath}',
      name: node.name,
      relPath: node.apiPath,
      serial: node.deviceSerial,
      hasLiveVideo: photo.hasLiveVideo,
      date: photo.mtime > 0
          ? DateTime.fromMillisecondsSinceEpoch(photo.mtime * 1000)
          : null,
      takenDate: photo.takenAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(photo.takenAt! * 1000),
    );
  }

  /// A Quark-stored photo in an album, keyed the way [_Photo.fromWire] keys
  /// the same photo in the library.
  factory _Photo.fromAlbumItem(PhotoAlbumItem item) => _Photo(
    id: '${item.deviceSerial}:${item.relPath}',
    name: item.relPath.split('/').last,
    relPath: item.relPath,
    serial: item.deviceSerial,
    date: item.addedAt,
    takenDate: item.takenAt,
  );

  /// A Quark-stored photo the files search found, keyed the way
  /// [_Photo.fromWire] keys the same photo in the library.
  factory _Photo.fromFile(FileNode file) => _Photo(
    id: '${file.deviceSerial}:${file.apiPath}',
    name: file.name,
    relPath: file.apiPath,
    serial: file.deviceSerial,
    date: file.modifiedAt,
  );

  /// A photo on this device.
  factory _Photo.fromAsset(AssetEntity asset) => _Photo(
    id: 'asset:${asset.id}',
    name: asset.id,
    asset: asset,
    // createDateTime reads a missing timestamp as 1970.
    date: asset.createDateSecond == null ? null : asset.createDateTime,
  );

  /// Unique across both sources, and stable across reloads.
  final String id;
  final String name;

  /// The Quark path, or null for a device photo.
  final String? relPath;
  final String? serial;

  /// The device asset, or null for a Quark photo.
  final AssetEntity? asset;
  final bool hasLiveVideo;

  /// When the photo was added, as the date-added sort sees it: the file's
  /// modified time on the Quark, the time it joined an album, or a device
  /// photo's creation time. Null when the Quark sent none.
  final DateTime? date;

  /// When the photo was taken, from its EXIF data, as the date-taken sort
  /// sees it (#2592). Null when the Quark has not read one, in which case the
  /// sort and its month headers stand in [date], the way the Quark orders it.
  /// A device photo's creation time already is its capture time, so it
  /// carries none and uses [date].
  final DateTime? takenDate;

  bool get isRemote => relPath != null;

  /// What a search matches: the file name, which for a device photo is its
  /// title, [name] being only its asset id.
  String get searchName => asset?.title ?? name;
}
