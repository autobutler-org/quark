import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/file_type_listing_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/error_text.dart';

/// Fetches every presentation on the Quark.
typedef ListSlidesFn = Future<List<FileNode>> Function();

/// Searches file contents for a query.
typedef SearchContentFn =
    Future<List<ContentSearchResult>> Function(String query);

/// Creates a presentation by name and returns its path.
typedef CreatePresentationFn = Future<String> Function(String name);

/// Imports the PowerPoint file at a path on the Quark as a presentation.
typedef ImportPowerPointFn =
    Future<PowerPointImport> Function(String path, {String? serial});

/// Uploads a PowerPoint file from this device and returns where it landed.
typedef UploadPowerPointFn = Future<String> Function(SlideFilePick pick);

/// Asks the user for a PowerPoint file on this device; null when they cancel.
typedef PickPowerPointFn = Future<SlideFilePick?> Function();

/// Lists a folder on the Quark, for picking a PowerPoint file from it.
typedef ListImportFolderFn = Future<List<FileNode>> Function(String path);

/// State behind the Slides page: the user's `.qslide` presentations, the
/// search over their names and contents, starting a new one, and importing
/// one from a PowerPoint file (#1171).
///
/// The listing comes from `FileTypeListingCache`, so the page shows the last
/// one on its first frame while a refresh runs, as Docs and Sheets do. A
/// failed refresh keeps the listing it had and sets [error]; the next good one
/// clears it, so a poll against an unreachable Quark does not blink the list
/// away and back.
class SlidesController extends ChangeNotifier {
  /// Every service call is a parameter defaulting to the real one, so a test
  /// passes fakes. [searchDebounce] is how long typing has to pause before the
  /// contents are searched.
  SlidesController({
    ListSlidesFn? listSlides,
    List<FileNode>? Function()? peekSlides,
    this.searchContent = ContentSearchService.search,
    this.createPresentation = SlidesService.create,
    this.importPowerPoint = SlidesService.importPowerPoint,
    this.uploadPowerPoint = SlidesService.uploadPowerPoint,
    this.pickPowerPoint = SlidesService.pickPowerPointFile,
    this.listFolder = SlidesService.listFolder,
    this.landingFolder = SlidesService.landingFolder,
    this.searchDebounce = const Duration(milliseconds: 400),
  }) : listSlides =
           listSlides ??
           (() => FileTypeListingCache.instance.fetch(SlidesService.fileType)),
       _files =
           (peekSlides ??
               () => FileTypeListingCache.instance.peek(
                 SlidesService.fileType,
               ))() ??
           const [];

  final ListSlidesFn listSlides;
  final SearchContentFn searchContent;
  final CreatePresentationFn createPresentation;
  final ImportPowerPointFn importPowerPoint;
  final UploadPowerPointFn uploadPowerPoint;
  final PickPowerPointFn pickPowerPoint;
  final ListImportFolderFn listFolder;

  /// The folder new files land in, where the PowerPoint picker opens.
  final String Function() landingFolder;
  final Duration searchDebounce;

  List<FileNode> _files;
  String _query = '';
  List<ContentSearchResult> _contentResults = const [];
  bool _contentSearching = false;
  Object? _error;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  bool _disposed = false;

  /// Every presentation from the last good listing, newest first.
  List<FileNode> get files => _files;

  /// The presentations whose name matches [query]; all of them with no query.
  List<FileNode> get filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _files;
    return [
      for (final f in _files)
        if (f.matchesSearch(q)) f,
    ];
  }

  /// The search text as typed.
  String get query => _query;

  /// Presentations whose contents match [query]. Hits in other file types are
  /// left out: only the slide editor can open these rows.
  List<ContentSearchResult> get contentResults => _contentResults;

  /// Whether a content search for [query] is still running.
  bool get contentSearching => _contentSearching;

  /// The thrown object from the last failed refresh, not its message — the
  /// page decides whether it means "your Quark is unreachable" or "the request
  /// failed" (#1637). Null after a good one.
  Object? get error => _error;

  /// Fetches the listing again.
  Future<void> refresh() async {
    try {
      _files = await listSlides();
      _error = null;
    } catch (e) {
      _error = e;
    }
    _notify();
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
    _notify();
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
      _contentResults = [
        for (final r in results)
          if (r.relPath.toLowerCase().endsWith(SlidesService.extension)) r,
      ];
      _contentSearching = false;
      _notify();
    });
  }

  /// Creates a presentation called [name] and returns its path. Throws what
  /// the service threw; the page reports it.
  Future<String> create(String name) => createPresentation(name);

  /// Imports the PowerPoint file at [path] on the Quark, beside itself.
  /// Throws what the service threw; the page reports it.
  Future<PowerPointImport> importFromQuark(String path) =>
      importPowerPoint(path);

  /// Uploads [pick] from this device into the folder new files land in, then
  /// imports it there. A failed upload is not imported, and a file that is
  /// not a PowerPoint file — a browser's picker lets any through — is not
  /// uploaded.
  Future<PowerPointImport> importFromDevice(SlideFilePick pick) async {
    if (!SlidesService.isPowerPoint(pick.name)) {
      throw const MessageException(Errors.notPowerPoint);
    }
    return importPowerPoint(await uploadPowerPoint(pick));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _searchTimer?.cancel();
    super.dispose();
  }
}
