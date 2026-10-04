import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/file_type_listing_cache.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/services/slides_service.dart';

/// Fetches every presentation on the Quark.
typedef ListSlidesFn = Future<List<FileNode>> Function();

/// Searches file contents for a query.
typedef SearchContentFn =
    Future<List<ContentSearchResult>> Function(String query);

/// Creates a presentation by name and returns its path.
typedef CreatePresentationFn = Future<String> Function(String name);

/// State behind the Slides page: the user's `.qslide` presentations, the
/// search over their names and contents, and starting a new one.
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
