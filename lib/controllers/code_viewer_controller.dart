import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:quark/services/code_viewer_service.dart';
import 'package:quark/utils/code_viewer_config.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

typedef ReadCodeRangeFn =
    Future<CodeViewerRange> Function(
      String path, {
      required int start,
      required int length,
      String? serial,
    });

/// State behind the code viewer for the file at [path]: the lines read so
/// far, whether more of the file is left on the Quark, the wrap setting and
/// the in-file search.
///
/// The file is read [pageBytes] at a time and only as far as the reader asks,
/// so opening a 1 GB log costs one page. Search covers the lines read so far.
class CodeViewerController extends ChangeNotifier with SafeNotifier {
  CodeViewerController({
    required this.path,
    this.serial,
    this.readRange = CodeViewerService.readRange,
    this.pageBytes = CodeViewerConfig.pageBytes,
    this.maxLineBytes = CodeViewerConfig.maxLineBytes,
  });

  /// The file's files-relative path.
  final String path;

  /// The device the file is on, null for the internal drive.
  final String? serial;

  final ReadCodeRangeFn readRange;

  /// How many bytes one request reads.
  final int pageBytes;

  /// The longest run of bytes without a newline kept as one line.
  final int maxLineBytes;

  List<String> _lines = const [];
  Uint8List _carry = Uint8List(0);
  int _offset = 0;
  int? _totalSize;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  Object? _error;
  Object? _loadMoreError;
  bool _wrap = false;
  String _query = '';
  List<CodeSearchMatch> _matches = const [];
  int? _activeMatch;
  int _generation = 0;

  /// The lines read so far, without their line endings. A new list each time
  /// a page lands.
  List<String> get lines => _lines;

  /// The language to highlight as: from the file's name, or a `#!` first line.
  CodeLanguage get language =>
      codeLanguageFor(path, firstLine: _lines.firstOrNull ?? '');

  /// Whether the first page is still out.
  bool get isLoading => _isLoading;

  /// What the first page failed with, null once one has loaded. The page
  /// turns it into a sentence.
  Object? get error => _error;

  /// Whether the Quark holds more of the file than has been read.
  bool get hasMore => _hasMore;

  /// Whether a later page is out.
  bool get isLoadingMore => _isLoadingMore;

  /// What the last later page failed with, null after one that worked.
  Object? get loadMoreError => _loadMoreError;

  /// How many bytes of the file have been read.
  int get loadedBytes => _offset;

  /// The file's size, null when the Quark did not say.
  int? get totalSize => _totalSize;

  /// Whether long lines wrap rather than scroll sideways.
  bool get wrap => _wrap;

  /// What the reader is searching for, empty when nothing.
  String get searchQuery => _query;

  /// Every hit for [searchQuery] in [lines], in order.
  List<CodeSearchMatch> get matches => _matches;

  /// The index into [matches] of the hit in view, null when there are none.
  int? get activeMatch => _activeMatch;

  /// Reads the file's first page, dropping whatever was read before.
  Future<void> load() async {
    final generation = ++_generation;
    _lines = const [];
    _carry = Uint8List(0);
    _offset = 0;
    _totalSize = null;
    _hasMore = false;
    _isLoading = true;
    _isLoadingMore = false;
    _error = null;
    _loadMoreError = null;
    _search();
    notifyListeners();
    try {
      await _readPage(generation);
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    }
    if (generation != _generation) return;
    _isLoading = false;
    notifyListeners();
  }

  /// Reads the next page, when there is one and none is already out.
  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final generation = _generation;
    _isLoadingMore = true;
    _loadMoreError = null;
    notifyListeners();
    try {
      await _readPage(generation);
    } catch (e) {
      if (generation != _generation) return;
      _loadMoreError = e;
    }
    if (generation != _generation) return;
    _isLoadingMore = false;
    notifyListeners();
  }

  /// Turns line wrapping on or off.
  void setWrap(bool wrap) {
    if (_wrap == wrap) return;
    _wrap = wrap;
    notifyListeners();
  }

  /// Searches the lines read so far for [query] and moves to the first hit.
  void setSearchQuery(String query) {
    if (_query == query) return;
    _query = query;
    _search();
    _activeMatch = _matches.isEmpty ? null : 0;
    notifyListeners();
  }

  /// Moves to the hit after the one in view, wrapping to the first.
  void nextMatch() => _step(1);

  /// Moves to the hit before the one in view, wrapping to the last.
  void previousMatch() => _step(-1);

  void _step(int by) {
    if (_matches.isEmpty) return;
    _activeMatch = ((_activeMatch ?? 0) + by) % _matches.length;
    notifyListeners();
  }

  Future<void> _readPage(int generation) async {
    final page = await readRange(
      path,
      start: _offset,
      length: pageBytes,
      serial: serial,
    );
    if (generation != _generation) return;
    final bytes = page.bytes;
    _offset += bytes.length;
    _totalSize = page.totalSize ?? _totalSize;
    final total = _totalSize;
    _hasMore =
        bytes.isNotEmpty &&
        (total != null ? _offset < total : bytes.length >= pageBytes);
    _append(bytes);
    // Earlier hits keep their place, so the hit in view stays the same one.
    _search();
  }

  /// Adds [bytes] to [lines], holding back an unfinished last line while more
  /// of the file is to come: a page ends wherever its byte count does, which
  /// can be mid-line and mid-character.
  void _append(Uint8List bytes) {
    final pending =
        (BytesBuilder(copy: false)
              ..add(_carry)
              ..add(bytes))
            .takeBytes();
    var end = pending.length;
    if (_hasMore) {
      end = pending.lastIndexOf(0x0A) + 1;
      // ponytail: a run this long with no newline is cut where the page
      // happened to end, which can split one character in two. Cut on a
      // UTF-8 boundary if minified files turn out to matter.
      if (end == 0 && pending.length >= maxLineBytes) end = pending.length;
    }
    _carry = Uint8List.sublistView(pending, end);
    if (end == 0) return;
    final text = utf8.decode(
      Uint8List.sublistView(pending, 0, end),
      allowMalformed: true,
    );
    final added = const LineSplitter().convert(text);
    _lines = [
      ..._lines,
      for (final line in added)
        for (var i = 0; i < line.length || i == 0; i += maxLineBytes)
          line.substring(i, (i + maxLineBytes).clamp(0, line.length)),
    ];
  }

  void _search() {
    _matches = findCodeMatches(
      _lines,
      _query,
      limit: CodeViewerConfig.maxSearchMatches,
    );
    final active = _activeMatch;
    _activeMatch = _matches.isEmpty
        ? null
        : (active ?? 0).clamp(0, _matches.length - 1);
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
