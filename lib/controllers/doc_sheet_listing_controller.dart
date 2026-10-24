import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/file_type_listing_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// Fetches every file of one type on the Quark.
typedef FetchListingFn = Future<List<FileNode>> Function(String fileType);

/// The last listing of one type, or null when there is none yet.
typedef PeekListingFn = List<FileNode>? Function(String fileType);

/// Writes [bytes] as [name] in [folder] and returns where it landed.
typedef UploadBytesFn =
    Future<List<String>> Function(
      String folder,
      String name,
      List<int> bytes, {
      String? serial,
      bool overwrite,
      bool keepBoth,
    });

/// State behind the Docs and Sheets pages, which are one page over two file
/// types: the [fileType] listing, the [otherType] listing that a search also
/// matches by name (#2259), the content search, and starting a new file.
///
/// Both listings come from `FileTypeListingCache`, so the page shows the last
/// ones on its first frame while a refresh runs (#1780). A failed refresh
/// keeps what it had and sets [error]; the next good one clears it, so a poll
/// against an unreachable Quark does not blink the list away and back.
class DocSheetListingController extends ChangeNotifier with SafeNotifier {
  /// Every service call is a parameter defaulting to the real one, so a test
  /// passes fakes.
  DocSheetListingController({
    required this.fileType,
    required this.otherType,
    required this.emptyFile,
    this.fetchListing = _fetchCached,
    PeekListingFn peekListing = _peekCached,
    this.searchContent = ContentSearchService.search,
    this.uploadBytes = FilesService.uploadBytes,
    this.landingFolder = _landingFolder,
  }) : _files = peekListing(fileType) ?? const [],
       _others = peekListing(otherType) ?? const [],
       _hasListing = peekListing(fileType) != null;

  /// The type this page lists, without the dot: `qdoc` or `qsheet`.
  final String fileType;

  /// The type a search also lists by name, in its own section.
  final String otherType;

  /// The contents a new [fileType] file starts with.
  final String emptyFile;

  final FetchListingFn fetchListing;
  final Future<List<ContentSearchResult>> Function(String query) searchContent;
  final UploadBytesFn uploadBytes;

  /// The folder new files land in. A member cannot write the device root,
  /// only their home (#2139).
  final String Function() landingFolder;

  /// How long typing has to pause before the contents are searched.
  static const searchDebounce = Duration(milliseconds: 400);

  static Future<List<FileNode>> _fetchCached(String type) =>
      FileTypeListingCache.instance.fetch(type);

  static List<FileNode>? _peekCached(String type) =>
      FileTypeListingCache.instance.peek(type);

  static String _landingFolder() => landingPath(
    isAdmin: AppSettings.instance.isAdmin.value,
    username: AppSettings.instance.username,
  );

  List<FileNode> _files;
  List<FileNode> _others;
  bool _hasListing;
  String _query = '';
  List<ContentSearchResult> _contentResults = const [];
  bool _contentSearching = false;
  Object? _error;
  Timer? _searchTimer;
  int _searchGeneration = 0;

  /// Every [fileType] file from the last good listing.
  List<FileNode> get files => _files;

  /// Every [otherType] file from the last good listing.
  List<FileNode> get others => _others;

  /// Whether a listing has arrived, from the cache or a refresh, so the page
  /// knows not to show its loader.
  bool get hasListing => _hasListing;

  /// The files a rename has to keep clear of: both types.
  List<FileNode> get siblings => [..._files, ..._others];

  String get _needle => _query.trim().toLowerCase();

  /// The [fileType] files whose name matches [query]; all of them with none.
  List<FileNode> get filtered => _needle.isEmpty
      ? _files
      : [
          for (final f in _files)
            if (f.matchesSearch(_needle)) f,
        ];

  /// The [otherType] files whose name matches [query]. Empty with no query:
  /// the other type only appears as search results, never as the library.
  List<FileNode> get otherFiltered => _needle.isEmpty
      ? const []
      : [
          for (final f in _others)
            if (f.matchesSearch(_needle)) f,
        ];

  /// The search text as typed.
  String get query => _query;

  /// Every content hit for [query], of any type; the body sorts them into
  /// sections by extension.
  List<ContentSearchResult> get contentResults => _contentResults;

  /// Whether a content search for [query] is still running.
  bool get contentSearching => _contentSearching;

  /// The thrown object from the last failed refresh, not its message — the
  /// body decides whether it means "your Quark is unreachable" or "the
  /// request failed" (#1637). Null after a good one.
  Object? get error => _error;

  /// Fetches both listings again.
  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        fetchListing(fileType),
        fetchListing(otherType),
      ]);
      _files = results[0];
      _others = results[1];
      _hasListing = true;
      _error = null;
    } catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  /// Filters by name at once, and searches contents once typing pauses.
  void setQuery(String query) {
    if (query == _query) return;
    _query = query;
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    final q = query.trim();
    _contentResults = const [];
    _contentSearching = q.isNotEmpty;
    notifyListeners();
    if (q.isEmpty) return;
    _searchTimer = Timer(searchDebounce, () async {
      List<ContentSearchResult> results;
      try {
        results = await searchContent(q);
      } catch (_) {
        // Name matches still show; a failed content search just adds none.
        results = const [];
      }
      if (generation != _searchGeneration) return;
      _contentResults = results;
      _contentSearching = false;
      notifyListeners();
    });
  }

  /// Writes a new, empty [fileType] file called [name] into the
  /// [landingFolder] and returns its path. Throws what the service threw; the
  /// page reports it.
  Future<String> create(String name) async {
    final fileName = name.endsWith('.$fileType') ? name : '$name.$fileType';
    final dir = landingFolder();
    final landed = await uploadBytes(dir, fileName, emptyFile.codeUnits);
    return landed.firstOrNull ?? (dir.isEmpty ? fileName : '$dir/$fileName');
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }
}
