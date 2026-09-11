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
import 'package:quark/services/favorites_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/storage_service.dart';
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
  });

  /// Photos the Quark added.
  final int added;

  /// Device photos, which cannot go into an album yet.
  final int skipped;

  /// Photos the Quark refused or never answered for.
  final int failed;
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
       _listDevices = listDevices,
       _uploadFiles = uploadFiles,
       _bytesCache = bytesCache ?? PhotoBytesCache.instance,
       _isWeb = isWeb;

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
  /// cannot see device photos, so it shows Quark photos only.
  bool get showsCategories => !_isWeb;

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
      _quarkLoaded &&
      _quark.length < _quarkTotal &&
      (_category == PhotoCategory.quark || _category == PhotoCategory.all);

  /// Whether the next page of Quark photos is in flight.
  bool get isLoadingMore => _isLoadingMore;

  /// Whether the last attempt to list Quark photos never reached the Quark.
  ///
  /// Without this the page would render "No photos yet", telling the user
  /// their library is empty when it is simply out of reach (#1637).
  bool get quarkUnreachable => _quarkUnreachable;

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

    final quarkPage = await quark;
    final mobilePhotos = await mobile;
    final favoriteKeys = await favorites;
    await albums;
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
    for (final photo in [..._quark, ..._mobile]) {
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

  /// Flips whether the Quark photo [id] is a favorite. Device photos cannot be
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
    }
    notifyListeners();
  }

  // ── Selection ──────────────────────────────────────────────────────────────

  /// Starts selecting photos, with nothing selected. With [addingTo], the
  /// selection is headed for that album.
  void enterSelectionMode({AlbumItem? addingTo}) {
    _selectionMode = true;
    _addingToAlbum = addingTo;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Stops selecting photos and forgets the selection.
  void exitSelectionMode() {
    _selectionMode = false;
    _addingToAlbum = null;
    _selectedIds.clear();
    notifyListeners();
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
  ///
  /// Device photos are counted as skipped, and a photo the Quark refuses as
  /// failed, so the page can say what happened.
  Future<AddToAlbumOutcome> addSelectedToAlbum(int albumId) async {
    var added = 0;
    var skipped = 0;
    var failed = 0;
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
      } catch (_) {
        failed++;
      }
    }
    exitSelectionMode();
    return AddToAlbumOutcome(added: added, skipped: skipped, failed: failed);
  }

  // ── Albums ─────────────────────────────────────────────────────────────────

  /// Reloads the album tree. A failure leaves the last tree in place.
  Future<void> loadAlbums() async {
    try {
      _albums = await _listAlbums(tree: true);
    } catch (e) {
      debugPrint('[photos_controller.dart] Error loading albums: $e');
    } finally {
      _albumsLoading = false;
      notifyListeners();
    }
  }

  /// A fresh copy of the album tree, for a picker that loads its own. Throws
  /// what the Quark threw.
  Future<List<AlbumItem>> fetchAlbums() async => [
    for (final album in await _listAlbums(tree: true)) album.toAlbumItem(),
  ];

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

  /// Expands the album [id], or folds it.
  void toggleAlbumExpanded(int id) {
    if (!_expandedAlbumIds.remove(id)) _expandedAlbumIds.add(id);
    notifyListeners();
  }

  /// Creates an album named [name], under [parentId] when given, and reloads
  /// the tree. Throws what the Quark threw.
  Future<void> createAlbum(String name, {int? parentId}) async {
    await _createAlbum(name, parentId: parentId);
    await loadAlbums();
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
