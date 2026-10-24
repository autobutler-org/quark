import 'package:flutter/foundation.dart';
import 'package:quark/models/duplicate_group.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/duplicates_config.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/photo_location.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything the duplicates page shows and does (#1666): the groups, which
/// copies are marked for deletion, and deleting them.
///
/// Nothing starts marked (#3362): a copy marked before the user chose it put
/// a delete one tap away on a phone. [selectSuggested] marks every identical
/// copy but the first in one go, since one is as good as another; similar
/// photos are never suggested, since they may differ in ways that matter.
/// Every group keeps at least one copy. A reload keeps the user's marks, and a
/// group made entirely of photos it has not shown before starts unmarked.
///
/// A similar group whose copies are each a different format and whose
/// perceptual hashes are all within
/// [DuplicatesConfig.samePictureMaxDistance] of each other is one picture
/// saved in several formats (`IMG_1.HEIC` and an exported `IMG_1.jpg`). Names
/// play no part: extensions only label the format. [setPreferredFormat] marks the other formats' copies in each such
/// group that has the preferred one. The preference lasts for this controller
/// only, carries over a reload, and applies to new groups as they appear; a
/// toggle afterwards wins until the preference changes again.
///
/// Each copy's location is [photoLocation]'s plain wording, never the
/// storage path (#2575).
///
/// Service calls arrive as function parameters defaulting to the real static
/// methods, so a test passes fakes without a mocking library.
class DuplicatesController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller talking to the real services unless overridden.
  DuplicatesController({
    Future<List<DuplicateGroup>> Function() getDuplicates =
        FilesService.getDuplicates,
    Future<List<StorageDevice>> Function() listDevices =
        StorageService.listDevices,
    Future<void> Function(
          String rootDir,
          String fileName, {
          String? deviceSerial,
        })
        deleteFile =
        FilesService.deleteFile,
    Uri Function(String filePath, {String? serial, String? size}) thumbnailUrl =
        FilesService.constructThumbnailUrl,
  }) : _getDuplicates = getDuplicates,
       _listDevices = listDevices,
       _deleteFile = deleteFile,
       _thumbnailUrl = thumbnailUrl;

  final Future<List<DuplicateGroup>> Function() _getDuplicates;
  final Future<List<StorageDevice>> Function() _listDevices;
  final Future<void> Function(
    String rootDir,
    String fileName, {
    String? deviceSerial,
  })
  _deleteFile;
  final Uri Function(String filePath, {String? serial, String? size})
  _thumbnailUrl;

  List<DuplicateGroupItem> _groups = const [];
  final Map<String, int?> _maxDistances = {};
  final Map<String, ({String serial, String relPath})> _paths = {};
  final Set<String> _selected = {};
  bool _isLoading = false;
  bool _isDeleting = false;
  Object? _error;
  String? _preferredFormat;

  /// The groups, as the package list shows them.
  List<DuplicateGroupItem> get groups => _groups;

  /// The ids of the copies marked for deletion.
  Set<String> get selectedIds => Set.unmodifiable(_selected);

  /// The copies marked for deletion, in the order the page lists them, for
  /// the confirmation to name every one, on screen or not.
  List<DuplicatePhotoItem> get selectedPhotos => [
    for (final group in _groups)
      for (final photo in group.photos)
        if (_selected.contains(photo.id)) photo,
  ];

  /// Whether [selectSuggested] would mark anything: some identical group has
  /// a copy beyond its first one left unmarked.
  bool get hasSuggestions => _groups.any(
    (g) => g.isExact && _suggested(g).any((id) => !_selected.contains(id)),
  );

  /// The format whose copy to keep in each same-picture group, or null for
  /// any.
  String? get preferredFormat => _preferredFormat;

  /// The formats found in the same-picture groups, sorted; empty when there
  /// are none, so nothing is offered.
  List<String> get formats => {
    for (final group in _groups)
      if (_isSamePicture(group))
        for (final photo in group.photos) _format(photo.id),
  }.toList()..sort();

  /// Whether the groups are loading.
  bool get isLoading => _isLoading;

  /// Whether marked copies are being deleted.
  bool get isDeleting => _isDeleting;

  /// Why the last load failed, or null. The page words it.
  Object? get error => _error;

  /// The path and drive of the copy [id], for its thumbnail to retry a busy
  /// Quark and backfill one it lacks (#3362); null for an unknown id.
  ({String path, String serial})? thumbnailSource(String id) {
    final path = _paths[id];
    return path == null ? null : (path: path.relPath, serial: path.serial);
  }

  /// The thumbnail of the copy [id].
  Uri? thumbnailUrl(String id) {
    final path = _paths[id];
    return path == null
        ? null
        : _thumbnailUrl(path.relPath, serial: path.serial);
  }

  /// Loads the groups, keeping the marks in every group it has shown before
  /// and marking none in a new one, unless a preferred format applies.
  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final groups = await _getDuplicates();
      final devices = await _deviceNames(groups);
      final seen = {..._paths.keys};
      final marked = {..._selected};
      _paths.clear();
      _selected.clear();
      _maxDistances
        ..clear()
        ..addAll({
          for (final (index, group) in groups.indexed)
            'g$index': group.maxDistance,
        });
      _groups = [
        for (final (index, group) in groups.indexed)
          DuplicateGroupItem(
            id: 'g$index',
            isExact: group.isExact,
            photos: [
              for (final photo in group.photos)
                _item(photo.deviceSerial, photo.relPath, devices),
            ],
          ),
      ];
      for (final group in _groups) {
        final ids = [for (final p in group.photos) p.id];
        if (ids.any(seen.contains)) {
          final kept = ids.where(marked.contains).toSet();
          // A group always keeps one copy, even when the one left unmarked
          // is the copy that went away.
          if (kept.length == ids.length) kept.remove(ids.first);
          _selected.addAll(kept);
        } else {
          _applyPreference(group);
        }
      }
    } catch (e) {
      _error = e;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Flips whether the copy [id] is marked, refusing to mark a group's last
  /// kept copy.
  void toggle(String id) {
    if (_selected.remove(id)) {
      notifyListeners();
      return;
    }
    final group = _groups.where((g) => g.photos.any((p) => p.id == id));
    if (group.isEmpty) return;
    final kept = group.first.photos.where((p) => !_selected.contains(p.id));
    if (kept.length <= 1) return;
    _selected.add(id);
    notifyListeners();
  }

  /// Marks the suggested copies: in each identical group, every copy but
  /// one. A group whose first copy the user marked keeps the first copy they
  /// left unmarked instead, so the suggestion never undoes a choice to keep.
  void selectSuggested() {
    for (final group in _groups.where((g) => g.isExact)) {
      _selected.addAll(_suggested(group));
    }
    notifyListeners();
  }

  /// Clears every mark.
  void clearSelection() {
    if (_selected.isEmpty) return;
    _selected.clear();
    notifyListeners();
  }

  /// Keeps [format]'s copy in each same-picture group that has one, marking
  /// the rest; null goes back to marking none. Same-picture groups the old or
  /// new preference applies to are re-marked; every other group, identical
  /// and merely similar ones included, is left alone.
  void setPreferredFormat(String? format) {
    if (format == _preferredFormat) return;
    final old = _preferredFormat;
    _preferredFormat = format;
    for (final group in _groups) {
      if (!_isSamePicture(group)) continue;
      final formats = {for (final p in group.photos) _format(p.id)};
      if (formats.contains(old) || formats.contains(format)) {
        _applyPreference(group);
      }
    }
    notifyListeners();
  }

  /// Moves every marked copy to the trash, then reloads. Returns how many
  /// could not be deleted; the page words that.
  Future<int> deleteSelected() async {
    if (_selected.isEmpty || _isDeleting) return 0;
    _isDeleting = true;
    notifyListeners();
    var failed = 0;
    for (final id in [..._selected]) {
      final path = _paths[id];
      if (path == null) continue;
      final slash = path.relPath.lastIndexOf('/');
      try {
        await _deleteFile(
          slash < 0 ? '' : path.relPath.substring(0, slash),
          path.relPath.substring(slash + 1),
          deviceSerial: path.serial.isEmpty ? null : path.serial,
        );
      } catch (_) {
        failed++;
      }
    }
    _isDeleting = false;
    await load();
    return failed;
  }

  /// Device names by serial, fetched only when a copy is on a drive other
  /// than the internal one. A failure falls back to the folder alone.
  Future<Map<String, String>> _deviceNames(List<DuplicateGroup> groups) async {
    final onDevices = groups.any(
      (g) => g.photos.any((p) => p.deviceSerial.isNotEmpty),
    );
    if (!onDevices) return const {};
    try {
      return {
        for (final d in await _listDevices())
          if (d.serial.isNotEmpty) d.serial: d.name,
      };
    } catch (_) {
      return const {};
    }
  }

  DuplicatePhotoItem _item(
    String serial,
    String relPath,
    Map<String, String> devices,
  ) {
    final id = '$serial:$relPath';
    _paths[id] = (serial: serial, relPath: relPath);
    return DuplicatePhotoItem(
      id: id,
      name: relPath.substring(relPath.lastIndexOf('/') + 1),
      location: photoLocation(
        relPath,
        deviceName: serial.isEmpty ? null : devices[serial] ?? serial,
      ),
    );
  }

  /// The copies [selectSuggested] marks in [group]: all but the first one not
  /// already marked.
  Iterable<String> _suggested(DuplicateGroupItem group) {
    final ids = [for (final p in group.photos) p.id];
    final keep = ids.firstWhere(
      (id) => !_selected.contains(id),
      orElse: () => ids.first,
    );
    return ids.where((id) => id != keep);
  }

  /// Marks the copies of [group] that are not in the preferred format, when it
  /// is a same-picture group holding one; otherwise marks none of them. The
  /// preferred copy is never marked, so the group keeps a copy.
  void _applyPreference(DuplicateGroupItem group) {
    final ids = [for (final p in group.photos) p.id];
    _selected.removeAll(ids);
    final preferred = _preferredFormat;
    if (preferred == null || !_isSamePicture(group)) return;
    if (!ids.any((id) => _format(id) == preferred)) return;
    _selected.addAll(ids.where((id) => _format(id) != preferred));
  }

  /// Whether [group] is one picture in several formats: similar rather than
  /// identical, every copy a different format, and every copy's perceptual
  /// hash within [DuplicatesConfig.samePictureMaxDistance] of every other's.
  bool _isSamePicture(DuplicateGroupItem group) {
    if (group.isExact || group.photos.length < 2) return false;
    final distance = _maxDistances[group.id];
    if (distance == null ||
        distance > DuplicatesConfig.samePictureMaxDistance) {
      return false;
    }
    final formats = {for (final p in group.photos) _format(p.id)};
    return formats.length == group.photos.length;
  }

  /// The file format of the copy [id], as the choice labels it: `JPEG` for
  /// `.jpg` and `.jpeg`, `TIFF` for `.tif` and `.tiff`, otherwise the
  /// extension in capitals.
  String _format(String id) {
    final name = _name(id);
    final ext = fileExtension(name).replaceFirst('.', '').toUpperCase();
    return switch (ext) {
      'JPG' => 'JPEG',
      'TIF' => 'TIFF',
      _ => ext,
    };
  }

  /// The file name of the copy [id].
  String _name(String id) {
    final relPath = _paths[id]?.relPath ?? '';
    return relPath.substring(relPath.lastIndexOf('/') + 1);
  }
}
