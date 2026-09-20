/// One folder or file somebody else shared, as a `SharedRootsSheet` lists it.
///
/// Only the root of each share is one of these: what sits inside it is reached
/// by opening it, so it needs no entry of its own.
class SharedRootItem {
  /// Creates the entry for the item at [path].
  const SharedRootItem({
    required this.path,
    required this.name,
    this.owner = '',
  });

  /// What the sheet hands back when this entry is tapped, and the suffix of
  /// its key. Unique within one sheet.
  final String path;

  /// The item's own name, without the folders holding it.
  final String name;

  /// The account or group that owns it, empty when nobody could be named.
  final String owner;
}
