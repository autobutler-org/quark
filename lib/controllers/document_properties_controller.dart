import 'package:flutter/foundation.dart';
import 'package:quark/services/previews_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Reads an office file's saved properties. See [PreviewsService.properties].
typedef LoadDocumentPropertiesFn =
    Future<DocumentProperties> Function(String path, {String? serial});

/// State behind a Properties sheet or the generic viewer's property rows
/// (#3275): the properties last read, whether they are still loading, and
/// what a read failed with.
///
/// A later [load] keeps the properties already shown until the new read
/// lands, and a read that fails leaves them in place. A read that a newer
/// one overtook is dropped.
class DocumentPropertiesController extends ChangeNotifier with SafeNotifier {
  /// Creates a controller for the file at [path].
  DocumentPropertiesController({
    required this.path,
    this.serial,
    this.loadProperties = PreviewsService.properties,
  });

  /// The file's files-relative path.
  final String path;

  /// The device the file is on, null for the internal drive.
  final String? serial;

  /// The read. A test passes a fake.
  final LoadDocumentPropertiesFn loadProperties;

  DocumentProperties? _properties;
  bool _isLoading = true;
  Object? _error;
  int _generation = 0;

  /// The properties last read, null before the first read lands.
  DocumentProperties? get properties => _properties;

  /// Whether the first read is still running.
  ///
  /// A later [load] keeps [properties] on screen, so this is false during a
  /// refresh and the sheet does not replace the rows with a loader.
  bool get isLoading => _isLoading && _properties == null;

  /// What the last read failed with, null once it has worked. The page turns
  /// it into a sentence.
  Object? get error => _error;

  /// Reads the properties, dropping a read that a newer one overtook.
  Future<void> load() async {
    final generation = ++_generation;
    _error = null;
    _isLoading = true;
    _notify();
    try {
      final properties = await loadProperties(path, serial: serial);
      if (generation != _generation || isDisposed) return;
      _properties = properties;
    } catch (e) {
      if (generation != _generation || isDisposed) return;
      _error = e;
    }
    _isLoading = false;
    _notify();
  }

  void _notify() {
    if (!isDisposed) notifyListeners();
  }
}
