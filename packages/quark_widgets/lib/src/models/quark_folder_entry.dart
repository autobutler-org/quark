import 'package:flutter/foundation.dart';

/// One folder a `QuarkFolderPicker` lists.
///
/// [path] is the Quark files path (`/` for the root) and the suffix of the
/// row key, with every `/` replaced by `_`. [name] is the label on the row.
/// The picker does not read the filesystem; the caller maps its own folder
/// type into this. [path] is unique within one listing.
@immutable
class QuarkFolderEntry {
  /// Creates an entry for the folder at [path], labeled [name].
  const QuarkFolderEntry({required this.path, required this.name});

  /// The Quark files path. `/` is the root.
  final String path;

  /// The name shown on the row.
  final String name;
}
