import 'package:flutter/foundation.dart';
import 'package:quark/models/file_version.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark/services/file_versions_service.dart';
import 'package:quark/services/sharing_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef ListFileVersionsFn = Future<List<FileVersion>> Function(String path);
typedef FileVersionContentFn =
    Future<Uint8List> Function(String path, String id);
typedef RestoreFileVersionFn =
    Future<FileVersion> Function(String path, String id);
typedef LoadPrincipalsFn = Future<SharePrincipals> Function();

/// State behind the version history sheet for the file at [path]: its saved
/// versions, the load error, and which version is being restored or fetched.
///
/// Authors are named from the sharing principals, the one account list a
/// member may read; it is fetched once and a failure only costs the names.
/// The signed-in account, [selfUserId], reads "You", the Quark itself
/// "System", and an account the list does not hold "Unknown user".
class FileVersionsController extends ChangeNotifier with SafeNotifier {
  FileVersionsController({
    required this.path,
    this.selfUserId,
    this.listVersions = FileVersionsService.list,
    this.loadContent = FileVersionsService.content,
    this.restoreVersion = FileVersionsService.restore,
    this.loadPrincipals = SharingService.principals,
  });

  /// The file's files-relative path on the internal drive.
  final String path;

  /// The signed-in account's id, null when unknown.
  final int? selfUserId;

  final ListFileVersionsFn listVersions;
  final FileVersionContentFn loadContent;
  final RestoreFileVersionFn restoreVersion;
  final LoadPrincipalsFn loadPrincipals;

  List<FileVersion> _versions = const [];
  Map<int, String>? _usernames;
  Object? _error;
  String? _busyId;
  int _generation = 0;

  /// What the last load failed with, null after one that worked. The page
  /// turns it into a sentence.
  Object? get error => _error;

  /// The id of the version being restored or fetched, null when idle.
  String? get busyId => _busyId;

  /// The versions as the Quark listed them, newest first, as the panel renders
  /// them.
  List<FileVersionItem> get items => [
    for (final version in _versions)
      FileVersionItem(
        id: version.id,
        createdAt: version.createdAt,
        sizeLabel: StorageDevice.formatBytes(version.size),
        author: _authorName(version.authorId),
        label: version.label,
        isNamed: version.isNamed,
      ),
  ];

  /// The version [id], or null when the listing does not hold it.
  FileVersion? versionFor(String id) {
    for (final version in _versions) {
      if (version.id == id) return version;
    }
    return null;
  }

  /// Fetches the versions. A failure keeps the last good listing and sets
  /// [error]; a slower earlier load never overwrites a newer one.
  Future<void> load() async {
    final generation = ++_generation;
    try {
      // Names are decoration: without them the list still loads.
      _usernames ??= await loadPrincipals().then<Map<int, String>?>(
        (principals) => {
          for (final user in principals.users) user.id: user.username,
        },
        onError: (_) => null,
      );
      final versions = await listVersions(path);
      if (isDisposed || generation != _generation) return;
      _versions = versions;
      _error = null;
    } catch (e) {
      if (isDisposed || generation != _generation) return;
      _error = e;
    }
    notifyListeners();
  }

  /// Puts the file back to version [id] and reloads the list, which now
  /// leads with the "Before restore" backup. Returns what went wrong, or null.
  Future<Object?> restore(String id) async {
    if (_busyId != null) return null;
    _setBusy(id);
    try {
      await restoreVersion(path, id);
      if (!isDisposed) await load();
      return null;
    } catch (e) {
      return e;
    } finally {
      _setBusy(null);
    }
  }

  /// The bytes of version [id], for a preview. Throws what the fetch threw.
  Future<Uint8List> content(String id) async {
    _setBusy(id);
    try {
      return await loadContent(path, id);
    } finally {
      _setBusy(null);
    }
  }

  String _authorName(int authorId) {
    if (authorId == 0) return 'System';
    if (authorId == selfUserId) return 'You';
    return _usernames?[authorId] ?? 'Unknown user';
  }

  void _setBusy(String? id) {
    if (isDisposed) return;
    _busyId = id;
    notifyListeners();
  }
}
