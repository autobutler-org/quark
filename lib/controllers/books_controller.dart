import 'package:flutter/foundation.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/books_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';

/// Fetches every book on the Quark.
typedef ListBooksFn = Future<List<FileNode>> Function();

/// Fetches the drives the Quark manages, to name the one a book is on.
typedef ListDrivesFn = Future<List<StorageDevice>> Function();

/// State behind the Books page (#1678): the PDFs and EPUBs the Quark found,
/// by title.
///
/// When the books span more than one drive, each one's
/// [FileNode.deviceName] names its drive — "Built-in storage", or the USB
/// drive's name — so two books of one name tell apart (#3980). A failed
/// refresh keeps the listing it had and sets [error]; the next good one
/// clears it, as on Slides.
class BooksController extends ChangeNotifier with SafeNotifier {
  /// [listBooks] and [listDrives] default to the real services, so a test
  /// passes fakes.
  BooksController({
    this.listBooks = BooksService.list,
    this.listDrives = StorageService.listDevices,
  });

  final ListBooksFn listBooks;
  final ListDrivesFn listDrives;

  /// What a book on the internal drive says it is on, as backups name it.
  static const builtInName = 'Built-in storage';

  /// What a book says it is on when its USB drive has no name the Quark gave.
  static const unnamedDriveName = 'USB drive';

  List<FileNode> _books = const [];
  Object? _error;

  /// Every book from the last good listing, by file name, case ignored.
  List<FileNode> get books => _books;

  /// The thrown object from the last failed refresh, not its message — the
  /// page decides what it means. Null after a good one.
  Object? get error => _error;

  /// Fetches the listing again.
  Future<void> refresh() async {
    try {
      final books = [...await listBooks()]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _books = await _named(books);
      _error = null;
    } catch (e) {
      _error = e;
    }
    notifyListeners();
  }

  /// [books] with their drive named, when they span more than one drive.
  /// A failed drive lookup still names the internal drive and calls the
  /// rest [unnamedDriveName]; it never fails the listing.
  Future<List<FileNode>> _named(List<FileNode> books) async {
    if ({for (final b in books) b.deviceSerial}.length < 2) return books;
    var names = const <String, String>{};
    try {
      names = {
        for (final d in await listDrives())
          if (d.serial.isNotEmpty && d.name.isNotEmpty) d.serial: d.name,
      };
    } catch (_) {}
    return [
      for (final b in books)
        FileNode(
          name: b.name,
          size: b.size,
          isDir: b.isDir,
          deviceName: b.deviceSerial.isEmpty
              ? builtInName
              : names[b.deviceSerial] ?? unnamedDriveName,
          devicePath: b.devicePath,
          deviceSerial: b.deviceSerial,
          dirPath: b.dirPath,
          fileType: b.fileType,
          compressedSize: b.compressedSize,
          modifiedAt: b.modifiedAt,
          devices: b.devices,
        ),
    ];
  }
}
