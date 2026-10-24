import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/services/code_viewer_service.dart';
import 'package:quark/utils/markdown_viewer_config.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// State behind the Markdown viewer for the file at [path]: the parsed
/// document, whether the source is showing instead, and which remote images
/// the reader has asked to load.
///
/// Markdown is parsed whole, so at most [maxBytes] of the file is read; a
/// longer file is rendered up to there and [isTruncated] says so.
class MarkdownViewerController extends ChangeNotifier with SafeNotifier {
  MarkdownViewerController({
    required this.path,
    this.serial,
    this.readRange = CodeViewerService.readRange,
    this.maxBytes = MarkdownViewerConfig.maxBytes,
  });

  /// The file's files-relative path.
  final String path;

  /// The device the file is on, null for the internal drive.
  final String? serial;

  final ReadCodeRangeFn readRange;

  /// The most bytes of the file read and rendered.
  final int maxBytes;

  QuarkMarkdownDocument _document = const QuarkMarkdownDocument.empty();
  int _loadedBytes = 0;
  int? _totalSize;
  bool _isLoading = true;
  Object? _error;
  bool _showSource = false;
  Set<String> _allowedRemoteImages = const {};
  int _generation = 0;

  /// What was read of the file, parsed.
  QuarkMarkdownDocument get document => _document;

  /// Whether the file is still being read.
  bool get isLoading => _isLoading;

  /// What the read failed with, null once it has worked. The page turns it
  /// into a sentence.
  Object? get error => _error;

  /// How many bytes of the file were read.
  int get loadedBytes => _loadedBytes;

  /// The file's size, null when the Quark did not say.
  int? get totalSize => _totalSize;

  /// Whether the file is longer than what was read and rendered.
  bool get isTruncated {
    final total = _totalSize;
    return total != null ? _loadedBytes < total : _loadedBytes >= maxBytes;
  }

  /// Whether the file's source shows in place of the rendered view.
  bool get showSource => _showSource;

  /// The remote image addresses the reader has asked to load. Nothing off
  /// the Quark is fetched until its address is in here.
  Set<String> get allowedRemoteImages => _allowedRemoteImages;

  /// Reads and parses the file, dropping what was read before.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final page = await readRange(
        path,
        start: 0,
        length: maxBytes,
        serial: serial,
      );
      if (generation != _generation) return;
      _loadedBytes = page.bytes.length;
      _totalSize = page.totalSize;
      _document = QuarkMarkdownDocument.parse(
        utf8.decode(page.bytes, allowMalformed: true),
      );
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Shows the source or the rendered view.
  void setShowSource(bool showSource) {
    if (_showSource == showSource) return;
    _showSource = showSource;
    notifyListeners();
  }

  /// Lets the remote image at [src] load, because the reader asked for it.
  void allowRemoteImage(String src) {
    if (_allowedRemoteImages.contains(src)) return;
    _allowedRemoteImages = {..._allowedRemoteImages, src};
    notifyListeners();
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
