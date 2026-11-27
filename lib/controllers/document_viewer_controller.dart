import 'package:flutter/foundation.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/previews_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Reads a document as the viewer's block model; [PreviewsService.document]
/// by default.
typedef LoadDocumentFn =
    Future<QuarkDocument> Function(String path, {String? serial});

/// Converts a document into a sibling `.qdoc`;
/// [FilesService.convertDocumentToQdoc] by default.
typedef ConvertDocumentFn =
    Future<DocumentConversion> Function(
      String path, {
      String? serial,
      bool overwrite,
    });

/// State behind the read-only document viewer for the file at [path]
/// (#3265): the document the Quark parsed, why it could not be read, and
/// whether "Open as Quark doc" is running.
///
/// The Quark does the reading: [load] asks for the block stream and holds
/// what comes back, and [convert] asks for the `.qdoc`. Both calls are
/// parameters, so a test passes fakes.
class DocumentViewerController extends ChangeNotifier with SafeNotifier {
  DocumentViewerController({
    required this.path,
    this.serial,
    this.loadDocument = PreviewsService.document,
    this.convertDocument = FilesService.convertDocumentToQdoc,
  });

  /// The file's files-relative path.
  final String path;

  /// The device the file is on, null for the internal drive.
  final String? serial;

  final LoadDocumentFn loadDocument;

  final ConvertDocumentFn convertDocument;

  QuarkDocument _document = const QuarkDocument.empty();
  bool _isLoading = true;
  Object? _error;
  bool _isConverting = false;
  int _generation = 0;

  /// The document, once read.
  QuarkDocument get document => _document;

  /// Whether the document is still being read.
  bool get isLoading => _isLoading;

  /// What the read failed with, null once it has worked. The page turns it
  /// into a sentence.
  Object? get error => _error;

  /// Whether a conversion to a `.qdoc` is running.
  bool get isConverting => _isConverting;

  /// Whether there is a document to convert: one that loaded.
  bool get canConvert => !_isLoading && _error == null && !_isConverting;

  /// Reads the document, dropping what was read before.
  Future<void> load() async {
    final generation = ++_generation;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final document = await loadDocument(path, serial: serial);
      if (generation != _generation) return;
      _document = document;
    } catch (e) {
      if (generation != _generation) return;
      _error = e;
    }
    _isLoading = false;
    notifyListeners();
  }

  /// Writes the document as a sibling `.qdoc` and says where it landed and
  /// what it left out. Throws what the request threw: an `ApiException` with
  /// status 409 when that `.qdoc` already exists and [overwrite] is off, for
  /// the page to ask about.
  Future<DocumentConversion> convert({bool overwrite = false}) async {
    _isConverting = true;
    notifyListeners();
    try {
      return await convertDocument(path, serial: serial, overwrite: overwrite);
    } finally {
      _isConverting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _generation++;
    super.dispose();
  }
}
