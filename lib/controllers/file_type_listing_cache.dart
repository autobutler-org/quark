import 'package:quark/models/file_node.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/listing_cache_config.dart';

/// The last `/files/by-type` listing for each file type, so Docs and Sheets
/// can show their list on the first frame while a refresh runs (#1780).
///
/// Entries are keyed by the active Quark and account as well as the type, so
/// switching Quarks or signing in as someone else never shows the previous
/// one's files. At most [ListingCacheConfig.maxListings] are kept, the least
/// recently used dropped first.
///
/// ```dart
/// final cached = FileTypeListingCache.instance.peek('qdoc');
/// final fresh = await FileTypeListingCache.instance.fetch('qdoc');
/// ```
class FileTypeListingCache {
  /// [fetcher] and [scope] default to the real service and the active
  /// Quark and account; a test passes its own.
  FileTypeListingCache({
    Future<List<FileNode>> Function(String fileType)? fetcher,
    String Function()? scope,
  }) : _fetcher = fetcher ?? FilesService.getFilesByType,
       _scope = scope ?? _activeScope;

  /// The cache every page shares.
  static final instance = FileTypeListingCache();

  final Future<List<FileNode>> Function(String fileType) _fetcher;
  final String Function() _scope;

  /// A map literal keeps insertion order, so the first key is the least
  /// recently used.
  final _entries = <String, List<FileNode>>{};

  static String _activeScope() =>
      '$apiBaseUrl\u0000${AppSettings.instance.username ?? ''}';

  String _key(String fileType) => '${_scope()}\u0000$fileType';

  /// The last listing of [fileType] fetched for the active Quark and
  /// account, or null when there is none yet.
  List<FileNode>? peek(String fileType) {
    final key = _key(fileType);
    final files = _entries.remove(key);
    if (files != null) _entries[key] = files;
    return files;
  }

  /// Fetches [fileType] and remembers the result. A failed fetch throws and
  /// leaves the previous listing in place.
  Future<List<FileNode>> fetch(String fileType) async {
    // Keyed before the request, so a Quark switched mid-request does not
    // file this answer under the new one.
    final key = _key(fileType);
    final files = List<FileNode>.unmodifiable(await _fetcher(fileType));
    _entries.remove(key);
    _entries[key] = files;
    while (_entries.length > ListingCacheConfig.maxListings) {
      _entries.remove(_entries.keys.first);
    }
    return files;
  }

  /// Forgets every listing.
  void clear() => _entries.clear();
}
