import 'package:flutter/foundation.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/books_service.dart';

/// Fetches every book on the Quark.
typedef ListBooksFn = Future<List<FileNode>> Function();

/// State behind the Books page (#1678): the PDFs and EPUBs the Quark found,
/// by title.
///
/// A failed refresh keeps the listing it had and sets [error]; the next good
/// one clears it, as on Slides.
class BooksController extends ChangeNotifier {
  /// [listBooks] defaults to the real service, so a test passes a fake.
  BooksController({this.listBooks = BooksService.list});

  final ListBooksFn listBooks;

  List<FileNode> _books = const [];
  Object? _error;
  bool _disposed = false;

  /// Every book from the last good listing, by file name, case ignored.
  List<FileNode> get books => _books;

  /// The thrown object from the last failed refresh, not its message — the
  /// page decides what it means. Null after a good one.
  Object? get error => _error;

  /// Fetches the listing again.
  Future<void> refresh() async {
    try {
      _books = [...await listBooks()]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _error = null;
    } catch (e) {
      _error = e;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
