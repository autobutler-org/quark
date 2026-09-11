import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/models/trash_item.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/services/trash_service.dart';
import 'package:quark/utils/error_text.dart';

typedef ListDevicesFn = Future<List<StorageDevice>> Function();
typedef ListTrashFn =
    Future<TrashListing> Function(String serial, {String deviceName});
typedef ListTrashContentsFn =
    Future<TrashContents> Function(
      String serial,
      String trashName,
      String path,
    );
typedef RestoreTrashFn =
    Future<List<String>> Function(String serial, List<TrashRef> items);
typedef DeleteTrashFn =
    Future<int> Function(String serial, List<TrashRef> items);
typedef EmptyTrashFn = Future<int> Function(String serial);

/// State behind the Trash page: either the trash root — every shown device's
/// trash merged into one listing, with the device filter — or one folder in
/// the trash being browsed, plus the selection and the restore and delete
/// calls.
///
/// The listing is handed to `FileBrowserView` as [FileNode]s so the trash
/// reuses the Files viewer. Each node's path is `.trash/<trashName>` for a
/// trashed item, or `.trash/<trashName>/<path>` for something inside a trashed
/// folder: unique, where the item really sits on the device, and enough to
/// address it in a restore or delete ([refFor]).
class TrashController extends ChangeNotifier {
  TrashController({
    TrashLocation? location,
    this.listDevices = StorageService.listDevices,
    this.listTrash = TrashService.listTrash,
    this.listContents = TrashService.listContents,
    this.restoreItems = TrashService.restore,
    this.deleteItems = TrashService.deletePermanently,
    this.emptyTrash = TrashService.empty,
    this.clock = DateTime.now,
  }) : _location = location;

  final ListDevicesFn listDevices;
  final ListTrashFn listTrash;
  final ListTrashContentsFn listContents;
  final RestoreTrashFn restoreItems;
  final DeleteTrashFn deleteItems;
  final EmptyTrashFn emptyTrash;
  final DateTime Function() clock;

  static const _trashPrefix = '.trash/';

  /// Never completes: "nothing fetched yet" must not read as an empty trash.
  static final Future<List<FileNode>> _notLoaded =
      Completer<List<FileNode>>().future;

  TrashLocation? _location;
  TrashContents? _contents;
  List<StorageDevice> _devices = const [];
  Set<String> _activeDevicePaths = {};
  Future<List<FileNode>> _listing = _notLoaded;
  List<FileNode>? _nodes;
  Map<String, TrashItem> _items = const {};
  int? _retentionDays;
  int _generation = 0;
  bool _selectionMode = false;
  final Set<String> _selectedPaths = {};

  /// The folder being browsed, or null at the trash root. A load that finds
  /// the folder gone moves this up to the nearest level that still exists.
  TrashLocation? get location => _location;

  /// The name of the trashed item being browsed, for the breadcrumbs. Null at
  /// the root or before its first listing.
  String? get itemName {
    final location = _location;
    final contents = _contents;
    if (location == null || contents == null) return null;
    final original = _segments(contents.originalPath);
    final depth = _segments(location.path).length;
    return original.length > depth
        ? original[original.length - depth - 1]
        : location.trashName;
  }

  /// The breadcrumb trail for the folder being browsed: the trashed item's
  /// name, then the path inside it, as `/album/2024`. Null at the root.
  String? get breadcrumbPath {
    final location = _location;
    if (location == null) return null;
    return '/${[itemName ?? '…', ..._segments(location.path)].join('/')}';
  }

  /// The folder a [breadcrumbPath] segment names. Null at the root.
  TrashLocation? locationAt(String crumbPath) {
    final location = _location;
    if (location == null) return null;
    return (
      serial: location.serial,
      trashName: location.trashName,
      // The first segment is the trashed item; the rest is inside it.
      path: _segments(crumbPath).skip(1).join('/'),
    );
  }

  /// Every attached device; the page shows a filter when there is more than one.
  List<StorageDevice> get devices => _devices;

  /// The `devicePath`s whose trash is shown.
  Set<String> get activeDevicePaths => _activeDevicePaths;

  /// The listing in flight or last fetched, for `FileBrowserView.filesFuture`.
  Future<List<FileNode>> get listing => _listing;

  /// The last good listing, shown while the next one loads.
  List<FileNode>? get nodes => _nodes;

  /// How many days an item stays in the trash. Null until the first root
  /// listing.
  int? get retentionDays => _retentionDays;

  bool get selectionMode => _selectionMode;
  Set<String> get selectedPaths => _selectedPaths;
  List<FileNode> get selectedNodes => [
    for (final node in _nodes ?? const <FileNode>[])
      if (_selectedPaths.contains(node.apiPath)) node,
  ];

  /// What a restore or delete of [node] sends, read back from its path.
  static TrashRef refFor(FileNode node) {
    final rest = node.apiPath.substring(_trashPrefix.length);
    final slash = rest.indexOf('/');
    return slash < 0
        ? TrashRef(rest)
        : TrashRef(rest.substring(0, slash), rest.substring(slash + 1));
  }

  /// Browses to [location] (null for the trash root) and loads it. Already
  /// there is a no-op, so a route that follows [location] after a climb does
  /// not list the same folder twice.
  Future<void> open(TrashLocation? location) async {
    if (location == _location) return;
    _location = location;
    _contents = null;
    _nodes = null;
    _items = const {};
    _listing = _notLoaded;
    _selectionMode = false;
    _selectedPaths.clear();
    await load();
  }

  /// Loads the devices, then the folder being browsed or, at the root, the
  /// trash of every active device.
  ///
  /// Never throws: a failed listing is carried by [listing], where the view
  /// renders it.
  Future<void> load() async {
    final generation = ++_generation;
    final location = _location;
    final future = location == null
        ? _loadRoot(generation)
        : _loadFolder(location, generation);
    _listing = future;
    notifyListeners();
    try {
      await future;
    } catch (e) {
      debugPrint('[trash_controller.dart] Failed to list the trash: $e');
    }
  }

  Future<List<FileNode>> _loadRoot(int generation) async {
    try {
      _devices = await listDevices();
      final paths = _devices.map((d) => d.devicePath).toSet();
      if (_activeDevicePaths.isEmpty ||
          !paths.containsAll(_activeDevicePaths)) {
        _activeDevicePaths = paths;
      }
    } catch (e) {
      // Keep what we had; the internal trash is still worth listing.
      debugPrint('[trash_controller.dart] Failed to load devices: $e');
    }

    final listings = await Future.wait([
      for (final (serial, name) in _targets())
        listTrash(serial, deviceName: name).catchError(
          // A drive unplugged since the devices call has no trash to show.
          (_) => const TrashListing(retentionDays: 0, items: []),
          test: (e) => e is ApiException && e.statusCode == 404,
        ),
    ]);
    if (generation != _generation) return _nodes ?? const <FileNode>[];
    final items = [for (final l in listings) ...l.items]
      ..sort((a, b) => b.trashedAt.compareTo(a.trashedAt));
    if (listings.isNotEmpty) {
      _retentionDays = listings.map((l) => l.retentionDays).reduce(max);
    }
    _setItems(items);
    return _nodes!;
  }

  /// Lists [location]. A folder that is gone — restored, deleted, or purged,
  /// here or from another client — is not an error: the listing climbs to the
  /// nearest level that still exists, the trash root at the top.
  Future<List<FileNode>> _loadFolder(
    TrashLocation location,
    int generation,
  ) async {
    TrashLocation? current = location;
    while (current != null) {
      try {
        final contents = await listContents(
          current.serial,
          current.trashName,
          current.path,
        );
        if (generation != _generation) return _nodes ?? const <FileNode>[];
        _location = current;
        _setContents(current, contents);
        return _nodes!;
      } on ApiException catch (e) {
        // 404: gone. 400: no longer a folder, or a deep link that never
        // named one.
        if (e.statusCode != 404 && e.statusCode != 400) rethrow;
        if (generation != _generation) return _nodes ?? const <FileNode>[];
        current = parentOf(current);
      }
    }
    _location = null;
    _contents = null;
    return _loadRoot(generation);
  }

  /// Shows or hides one device's trash. Hiding the last one shows them all.
  Future<void> toggleDevice(String devicePath) {
    if (_activeDevicePaths.contains(devicePath)) {
      _activeDevicePaths = {..._activeDevicePaths}..remove(devicePath);
      if (_activeDevicePaths.isEmpty) {
        _activeDevicePaths = _devices.map((d) => d.devicePath).toSet();
      }
    } else {
      _activeDevicePaths = {..._activeDevicePaths, devicePath};
    }
    return load();
  }

  /// The row's second line: where the item would be restored to and how long
  /// it has. Inside a trashed folder that is the folder's original location
  /// and the trashed folder's days left.
  String? subtitleFor(FileNode node) {
    final contents = _contents;
    final String? folder;
    final int days;
    if (_location != null && contents != null) {
      folder = contents.originalPath.isEmpty
          ? null
          : '/${contents.originalPath}';
      days = contents.daysLeft(clock());
    } else {
      final item = _items[node.apiPath];
      if (item == null) return null;
      folder = item.originalFolder;
      days = item.daysLeft(clock());
    }
    final from = folder == null ? 'Original location unknown' : 'From $folder';
    final left = switch (days) {
      0 => 'deleted within the hour',
      1 => '1 day left',
      _ => '$days days left',
    };
    return '$from · $left';
  }

  // ── Selection ────────────────────────────────────────────────────────────

  void toggleSelection(FileNode node, {required bool enterSelectionMode}) {
    if (enterSelectionMode && !_selectionMode) {
      _selectionMode = true;
      _selectedPaths.clear();
    }
    if (!_selectedPaths.remove(node.apiPath)) _selectedPaths.add(node.apiPath);
    notifyListeners();
  }

  void selectAll() {
    _selectedPaths.addAll((_nodes ?? const []).map((n) => n.apiPath));
    notifyListeners();
  }

  void deselectAll() {
    _selectedPaths.clear();
    notifyListeners();
  }

  void exitSelection() {
    _selectionMode = false;
    _selectedPaths.clear();
    notifyListeners();
  }

  // ── Mutations ────────────────────────────────────────────────────────────

  /// Restores [nodes], one request per device, and returns how many came back.
  Future<int> restore(List<FileNode> nodes) async {
    final restored = await _perDevice(nodes, restoreItems);
    return restored.fold<int>(0, (sum, paths) => sum + paths.length);
  }

  /// Deletes [nodes] for good, one request per device, and returns how many.
  Future<int> deletePermanently(List<FileNode> nodes) async {
    final deleted = await _perDevice(nodes, deleteItems);
    return deleted.fold<int>(0, (sum, count) => sum + count);
  }

  /// Empties the trash of every device shown and returns how many items went.
  Future<int> empty() async {
    var total = 0;
    for (final (serial, _) in _targets()) {
      total += await emptyTrash(serial);
      _setItems([
        for (final item in _items.values)
          if (item.deviceSerial != serial) item,
      ]);
    }
    return total;
  }

  /// Runs [call] once per device over [nodes]. Each device's nodes leave the
  /// listing as soon as its call succeeds, so a failure on a later device
  /// does not strand the earlier ones on screen until the next refresh.
  Future<List<T>> _perDevice<T>(
    List<FileNode> nodes,
    Future<T> Function(String serial, List<TrashRef> items) call,
  ) async {
    final bySerial = <String, List<FileNode>>{};
    for (final node in nodes) {
      (bySerial[node.deviceSerial] ??= []).add(node);
    }
    final results = <T>[];
    for (final MapEntry(key: serial, value: batch) in bySerial.entries) {
      results.add(await call(serial, batch.map(refFor).toList()));
      final gone = batch.map((n) => n.apiPath).toSet();
      _items = {
        for (final e in _items.entries)
          if (!gone.contains(e.key)) e.key: e.value,
      };
      _showNodes([
        for (final n in _nodes ?? const <FileNode>[])
          if (!gone.contains(n.apiPath)) n,
      ]);
    }
    if (_selectionMode) exitSelection();
    return results;
  }

  /// The devices whose trash to list, as (serial, display name). A USB drive
  /// with no serial is left out: the API reads the empty serial as the
  /// internal disk.
  List<(String, String)> _targets() {
    if (_devices.isEmpty) return const [('', '')];
    final seen = <String>{};
    return [
      for (final d in _devices)
        if (_activeDevicePaths.contains(d.devicePath) &&
            (d.isInternal || d.serial.isNotEmpty) &&
            seen.add(d.serial))
          (d.serial, d.name.isNotEmpty ? d.name : d.mountPoint),
    ];
  }

  void _setItems(List<TrashItem> items) {
    final byPath = <String, TrashItem>{};
    final nodes = <FileNode>[];
    for (final item in items) {
      final node = FileNode(
        name: item.name,
        size: item.size,
        isDir: item.isDir,
        deviceName: item.deviceName,
        devicePath: '',
        deviceSerial: item.deviceSerial,
        dirPath: '$_trashPrefix${item.trashName}',
      );
      byPath[node.apiPath] = item;
      nodes.add(node);
    }
    _items = byPath;
    _showNodes(nodes);
  }

  void _setContents(TrashLocation location, TrashContents contents) {
    _contents = contents;
    _items = const {};
    _showNodes([
      for (final child in contents.items)
        FileNode(
          name: child.name,
          size: child.size,
          isDir: child.isDir,
          deviceName: '',
          devicePath: '',
          deviceSerial: location.serial,
          dirPath: '$_trashPrefix${location.trashName}/${child.path}',
        ),
    ]);
  }

  void _showNodes(List<FileNode> nodes) {
    _nodes = nodes;
    _selectedPaths.retainAll(nodes.map((n) => n.apiPath));
    // Keep the view's future in step with what is on screen.
    _listing = Future.value(nodes);
    notifyListeners();
  }

  static List<String> _segments(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  /// One level up from [location], or null — the trash root — above the
  /// trashed item itself.
  static TrashLocation? parentOf(TrashLocation location) {
    if (location.path.isEmpty) return null;
    final segments = _segments(location.path);
    return (
      serial: location.serial,
      trashName: location.trashName,
      path: segments.take(segments.length - 1).join('/'),
    );
  }
}
