import 'package:flutter/foundation.dart';
import 'package:quark/controllers/photos_controller.dart'
    show AddToAlbumOutcome;
import 'package:quark/models/photo_album.dart';
import 'package:quark/models/photo_locations.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/photo_locations_service.dart';
import 'package:quark/utils/location_clusters.dart';
import 'package:quark/utils/photo_map_config.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Whether the Locations view shows its map or the list standing in for it.
enum LocationsView {
  /// The map with its markers.
  map,

  /// One row per cluster, for a keyboard or a screen reader.
  list,
}

/// Everything the Locations view shows and does (#3557): where the account's
/// photos were taken, clustered for the map's zoom, the cluster whose photos
/// are open, and adding some of them to an album.
///
/// A view of the library and nothing more: it reads positions the Quark
/// already stored from each photo's EXIF, and adding to an album goes
/// through the same album call the library uses, which records a pointer to
/// the photo and copies nothing.
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class PhotoLocationsController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  PhotoLocationsController({
    Future<PhotoLocations> Function() fetchLocations =
        PhotoLocationsService.fetch,
    Future<List<PhotoAlbum>> Function({bool tree}) listAlbums =
        AlbumService.listAlbums,
    Future<bool> Function(
          int albumId, {
          required String deviceSerial,
          required String relPath,
        })
        addPhotoToAlbum =
        AlbumService.addPhotoToAlbum,
    Uri Function(String filePath, {String? serial, String? size}) thumbnailUrl =
        FilesService.constructThumbnailUrl,
  }) : _fetch = fetchLocations,
       _listAlbums = listAlbums,
       _addPhotoToAlbum = addPhotoToAlbum,
       _thumbnailUrl = thumbnailUrl;

  final Future<PhotoLocations> Function() _fetch;
  final Future<List<PhotoAlbum>> Function({bool tree}) _listAlbums;
  final Future<bool> Function(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  })
  _addPhotoToAlbum;
  final Uri Function(String filePath, {String? serial, String? size})
  _thumbnailUrl;

  PhotoLocations _locations = PhotoLocations.empty;
  bool _loaded = false;
  bool _isLoading = false;
  Object? _error;
  int _zoom = 2;
  final Map<int, List<LocationCluster>> _clusters = {};
  LocationCluster? _selected;
  LocationsView _view = LocationsView.map;
  final Set<String> _selectedIds = {};

  /// What the Quark last reported.
  PhotoLocations get locations => _locations;

  /// Whether a first load has finished, failed or not.
  bool get loaded => _loaded;

  /// Whether a load is in flight.
  bool get isLoading => _isLoading;

  /// Why the last load failed, or null. The page words it.
  Object? get error => _error;

  /// The map's whole zoom level.
  int get zoom => _zoom;

  /// The clusters at the current zoom, largest first.
  List<LocationCluster> get clusters => _clustersAt(_zoom);

  /// The clusters the list shows, at [PhotoMapConfig.listZoom] whatever the
  /// map's zoom: about a town each, which reads as a place.
  List<LocationCluster> get listClusters =>
      _clustersAt(PhotoMapConfig.listZoom);

  List<LocationCluster> _clustersAt(int zoom) => _clusters.putIfAbsent(
    zoom,
    () => clusterLocations(_locations.points, zoom),
  );

  /// The cluster whose photos are open, or null.
  LocationCluster? get selected => _selected;

  /// The map or the list.
  LocationsView get view => _view;

  /// The selected cluster's photos, as the grid shows them, newest first.
  List<PhotoItem> get selectedPhotos => [
    for (final p in _selected?.points ?? const <PhotoLocationPoint>[])
      PhotoItem(id: p.id, name: p.fileName),
  ];

  /// The ids of the photos picked in the open cluster.
  Set<String> get selectedIds => Set.unmodifiable(_selectedIds);

  /// Loads the positions. A failure keeps what was shown before.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _locations = await _fetch();
      _error = null;
      _clusters.clear();
      _reselect();
    } catch (e) {
      _error = e;
    } finally {
      _isLoading = false;
      _loaded = true;
      notifyListeners();
    }
  }

  /// Clusters for the map's new whole [zoom] level. The open cluster stays
  /// open: its photos do not change because the map moved.
  void setZoom(int zoom) {
    if (zoom == _zoom) return;
    _zoom = zoom;
    notifyListeners();
  }

  /// Shows the map or the list.
  void setView(LocationsView view) {
    if (view == _view) return;
    _view = view;
    notifyListeners();
  }

  /// Opens [cluster]'s photos.
  void select(LocationCluster cluster) {
    _selected = cluster;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Closes the open cluster, back to the map as it was.
  void closeSelection() {
    if (_selected == null) return;
    _selected = null;
    _selectedIds.clear();
    notifyListeners();
  }

  /// Picks or unpicks the photo at [index] of the open cluster.
  void toggleSelection(int index) {
    final id = _selected!.points[index].id;
    if (!_selectedIds.remove(id)) _selectedIds.add(id);
    notifyListeners();
  }

  /// The photo at [index] of the open cluster.
  PhotoLocationPoint pointAt(int index) => _selected!.points[index];

  /// The thumbnail of [point].
  Uri thumbnailUrl(PhotoLocationPoint point) =>
      _thumbnailUrl(point.relPath, serial: point.serial);

  /// The point behind a grid photo's [id], for its thumbnail.
  PhotoLocationPoint? pointFor(String id) {
    for (final p in _selected?.points ?? const <PhotoLocationPoint>[]) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// The albums a selection can go into.
  Future<List<AlbumItem>> fetchAlbums() async =>
      (await _listAlbums(tree: true)).toUserAlbumItems();

  /// Adds the picked photos to [albumId], each as the library does it: a
  /// pointer to the photo where it already is. Clears the selection once
  /// any went in.
  Future<AddToAlbumOutcome> addSelectedToAlbum(int albumId) async {
    var added = 0;
    var alreadyIn = 0;
    var failed = 0;
    Object? error;
    for (final p in _selected?.points ?? const <PhotoLocationPoint>[]) {
      if (!_selectedIds.contains(p.id)) continue;
      try {
        final isNew = await _addPhotoToAlbum(
          albumId,
          deviceSerial: p.serial,
          relPath: p.relPath,
        );
        isNew ? added++ : alreadyIn++;
      } catch (e) {
        failed++;
        error = e;
      }
    }
    if (added + alreadyIn > 0) {
      _selectedIds.clear();
      notifyListeners();
    }
    return AddToAlbumOutcome(
      added: added,
      alreadyIn: alreadyIn,
      skipped: 0,
      failed: failed,
      error: error,
    );
  }

  /// After a reload, keeps the open cluster open with its new members, or
  /// closes it when it is gone.
  void _reselect() {
    final open = _selected;
    if (open == null) return;
    final zoom = int.parse(open.id.split('/').first);
    _selected = _clustersAt(zoom).where((c) => c.id == open.id).firstOrNull;
    if (_selected == null) _selectedIds.clear();
  }
}
