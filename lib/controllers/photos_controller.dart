import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:photo_manager/photo_manager.dart';
import 'package:quark/controllers/photo_bytes_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/paginated_photos_response.dart' as wire;
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/demo_photos_service.dart';
import 'package:quark/services/favorites_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/album_link.dart' as link;
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/photo_grid_config.dart';
import 'package:quark/utils/quark_widget_items.dart';
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
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class PhotosController extends ChangeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  PhotosController({
    Future<wire.PaginatedPhotosResponse> Function({
          int offset,
          int limit,
          String? serial,
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
    Future<List<PhotoAlbumItem>> Function(int albumId) listAlbumItems =
        AlbumService.listAlbumItems,
    Future<List<StorageDevice>> Function() listDevices =
        StorageService.listDevices,
    Future<http.StreamedResponse> Function(
          String uploadPath,
          List<http.MultipartFile> files, {
          String? serial,
          bool overwrite,
        })
        uploadFiles =
        FilesService.uploadFilesFromFormData,
    PhotoBytesCache? bytesCache,
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
       _bytesCache = bytesCache ?? PhotoBytesCache.instance,
       _isWeb = isWeb;

  /// A controller over Demo mode's bundled sample library (#1746).
  ///
  /// Every Quark-bound photo and album call is swapped for its
  /// [DemoPhotosService] stand-in, so nothing it shows comes from, or is
  /// asked of, a Quark. Device photos and uploads are left as they are.
  factory PhotosController.demo() => PhotosController(
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
    listAlbumItems: (id) async => DemoPhotosService.listAlbumItems(id),
  );

  /// How many Quark photos one page fetches.
  static const int pageSize = 50;

  /// How many device photos the first (and only) page fetches.
  static const int deviceAssetPageSize = 200;

  final Future<wire.PaginatedPhotosResponse> Function({
    int offset,
    int limit,
    String? serial,
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
  final Future<List<PhotoAlbumItem>> Function(int albumId) _listAlbumItems;
  final Future<List<StorageDevice>> Function() _listDevices;
  final Future<http.StreamedResponse> Function(
    String uploadPath,
    List<http.MultipartFile> files, {
    String? serial,
    bool overwrite,
  })
  _uploadFiles;
  final PhotoBytesCache _bytesCache;
  final bool _isWeb;

  // ── Photos ─────────────────────────────────────────────────────────────────

  List<_Photo> _quark = const [];
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

  // ── Selection ──────────────────────────────────────────────────────────────

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  AlbumItem? _addingToAlbum;

  // ── Albums ─────────────────────────────────────────────────────────────────

  List<PhotoAlbum> _albums = const [];
  bool _albumsLoading = true;
  final Set<int> _expandedAlbumIds = {};

  /// The album the grid was asked to show, or null for the library.
  int? _albumId;

  /// An `?album=` value waiting for the tree's first successful load to be
  /// resolved into [_albumId]. Null once resolved, and for the library. A
  /// failed load keeps it, so an unreachable Quark never erases a shared link.
  String? _pendingLink;

  /// The items of [_albumId], null until they arrive or when they failed.
  List<_Photo>? _albumItems;
  Object? _albumError;

  /// Bumped by every album items request, so a slow answer for an album the
  /// user has already left cannot land on the one they moved to.
  int _albumRequest = 0;

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

  /// Whether another page of Quark photos exists and the grid shows them.
  bool get hasMore =>
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

  /// The album tree in display order: system albums first, favorites leading
  /// them, then the user's.
  List<AlbumItem> get albums {
    final system = _albums.where((a) => a.isSystemAlbum).toList()
      ..sort((a, b) {
        if (a.isFavorites) return -1;
        if (b.isFavorites) return 1;
        return 0;
      });
    return [
      for (final album in system) album.toAlbumItem(),
      for (final album in _albums.where((a) => !a.isSystemAlbum))
        album.toAlbumItem(),
    ];
  }

  /// Whether the album tree has yet to load for the first time.
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
  /// never blanks the grid.
  Future<void> refresh() async {
    final generation = ++_generation;
    final noHost = _activeHost() == null;

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

    final quarkPage = await quark;
    final mobilePhotos = await mobile;
    final favoriteKeys = await favorites;
    await albums;
    await albumItems;
    if (generation != _generation || _disposed) return;

    _noHostSelected = noHost;
    _mobile = mobilePhotos;
    if (favoriteKeys != null) {
      _favoriteKeys
        ..clear()
        ..addAll(favoriteKeys);
    }
    if (quarkPage == null) {
      // No host is a different state with its own UI, so nothing left over
      // from the host that was just removed may outlive it.
      _quark = const [];
      _quarkTotal = 0;
      _quarkLoaded = false;
      _quarkUnreachable = false;
    } else {
      _quark = quarkPage.photos;
      _quarkTotal = quarkPage.total;
      _quarkLoaded = true;
      _quarkUnreachable = quarkPage.unreachable;
    }
    notifyListeners();
  }

  /// Fetches the next page of Quark photos, if there is one and none is
  /// already in flight.
  Future<void> loadMoreQuarkPhotos() async {
    // Album items arrive in one call; paging is the library's alone.
    if (_showsAlbum) return;
    if (_isLoadingMore || !_quarkLoaded || _noHostSelected) return;
    if (_quark.length >= _quarkTotal) return;
    final generation = _generation;

    _isLoadingMore = true;
    notifyListeners();
    try {
      final response = await _getPhotos(offset: _quark.length, limit: pageSize);
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
      final response = await _getPhotos(offset: 0, limit: pageSize);
      return (
        photos: response.photos.map(_Photo.fromWire).toList(growable: false),
        total: response.total,
        unreachable: false,
      );
    } catch (e) {
      debugPrint('[photos_controller.dart] Error loading photos: $e');
      return (
        photos: const <_Photo>[],
        total: 0,
        unreachable: isQuarkUnreachableError(e),
      );
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
    if (_showsAlbum) return _albumItems ?? const [];
    if (_isWeb) return _quark;
    return switch (_category) {
      PhotoCategory.quark => _quark,
      PhotoCategory.mobile => _mobile,
      PhotoCategory.all => [..._quark, ..._mobile],
      PhotoCategory.favorites => [
        for (final photo in [..._quark, ..._mobile])
          if (_favoriteKeys.contains(photo.id)) photo,
      ],
    };
  }

  _Photo? _byId(String id) {
    for (final photo in [..._quark, ..._mobile, ...?_albumItems]) {
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
    super.dispose();
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

  /// Reloads the album tree. A failure leaves the last tree in place.
  ///
  /// A successful load also resolves an `?album=` value still pending, and
  /// loads that album's items. A failed one leaves the value pending for the
  /// next load, whether a manual refresh, a pull, or a resume.
  Future<void> loadAlbums() async {
    var loaded = false;
    try {
      _albums = await _listAlbums(tree: true);
      loaded = true;
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
  /// All photos for null, in whichever category was showing. Selection is a
  /// library feature, so showing an album ends it.
  Future<void> showAlbum(int? id) async {
    _pendingLink = null;
    if (id == _albumId) return;
    _albumId = id;
    _albumItems = null;
    _albumError = null;
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
  /// on a failed load, the value replaces the one waiting.
  Future<void> showAlbumLink(String? value) async {
    final wanted = value == null || value.isEmpty ? null : value;
    if (!_albumsLoading && _pendingLink == null) {
      await showAlbum(
        wanted == null ? null : link.resolveAlbumLink(_albums, wanted)?.id,
      );
      return;
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

  /// Loads the items of the album being shown, if any. A failure is kept for
  /// the page to word, in place of the items.
  Future<void> _loadAlbumItems() async {
    final id = _albumId;
    if (id == null) return;
    final request = ++_albumRequest;
    try {
      final items = await _listAlbumItems(id);
      if (request != _albumRequest || _disposed) return;
      _albumItems = items.map(_Photo.fromAlbumItem).toList(growable: false);
      _albumError = null;
    } catch (e) {
      if (request != _albumRequest || _disposed) return;
      debugPrint('[photos_controller.dart] Error loading album items: $e');
      _albumItems = null;
      _albumError = e;
    }
    notifyListeners();
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
  Future<void> uploadPhotos(List<PlatformFile> files, {String? serial}) async {
    _isUploading = true;
    notifyListeners();
    try {
      final multipart = <http.MultipartFile>[
        for (final file in files)
          if (!_isWeb && (file.path ?? '').isNotEmpty)
            await http.MultipartFile.fromPath(
              'files',
              file.path!,
              filename: file.name,
            )
          else
            http.MultipartFile.fromBytes(
              'files',
              await file.readAsBytes(),
              filename: file.name,
            ),
      ];
      await _uploadFiles('', multipart, serial: serial);
    } finally {
      _isUploading = false;
      notifyListeners();
    }
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

/// The first page of Quark photos, or why there is none.
typedef _QuarkPage = ({List<_Photo> photos, int total, bool unreachable});

/// One photo from either source, with what the services need to reach it.
class _Photo {
  const _Photo({
    required this.id,
    required this.name,
    this.relPath,
    this.serial,
    this.asset,
    this.hasLiveVideo = false,
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
    );
  }

  /// A Quark-stored photo in an album, keyed the way [_Photo.fromWire] keys
  /// the same photo in the library.
  factory _Photo.fromAlbumItem(PhotoAlbumItem item) => _Photo(
    id: '${item.deviceSerial}:${item.relPath}',
    name: item.relPath.split('/').last,
    relPath: item.relPath,
    serial: item.deviceSerial,
  );

  /// A photo on this device.
  factory _Photo.fromAsset(AssetEntity asset) =>
      _Photo(id: 'asset:${asset.id}', name: asset.id, asset: asset);

  /// Unique across both sources, and stable across reloads.
  final String id;
  final String name;

  /// The Quark path, or null for a device photo.
  final String? relPath;
  final String? serial;

  /// The device asset, or null for a Quark photo.
  final AssetEntity? asset;
  final bool hasLiveVideo;

  bool get isRemote => relPath != null;
}
