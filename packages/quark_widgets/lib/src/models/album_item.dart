import 'package:flutter/foundation.dart';

/// One album as the widgets need it: a name, a count, and its children.
///
/// The package's own view of an album, so no widget has to import the app's
/// model. Controllers map their album type into this at the edge, and map back
/// by [id] when a callback comes out.
@immutable
class AlbumItem {
  /// Creates an album node.
  const AlbumItem({
    required this.id,
    required this.name,
    this.parentId,
    this.itemCount = 0,
    this.isSystem = false,
    this.isFavorites = false,
    this.children = const [],
  });

  /// The album's stable identifier, and what callbacks are matched on.
  final int id;

  /// The album's display name.
  final String name;

  /// The parent album's [id], or null for a top-level album.
  final int? parentId;

  /// How many photos the album holds. Zero hides the count badge.
  final int itemCount;

  /// Whether the Quark maintains this album rather than the user, which is
  /// what suppresses rename and delete.
  final bool isSystem;

  /// Whether this is the favorites album, which gets its own glyph.
  final bool isFavorites;

  /// Sub-albums, rendered under this one when it is expanded.
  final List<AlbumItem> children;

  /// Every album in [roots] and their descendants, parents before children,
  /// each paired with how deep it sits (zero for a root).
  ///
  /// For a widget that lists a whole tree flat with an indent, such as a
  /// picker sheet.
  static Iterable<(AlbumItem, int)> depthFirst(
    List<AlbumItem> roots, [
    int depth = 0,
  ]) sync* {
    for (final album in roots) {
      yield (album, depth);
      yield* depthFirst(album.children, depth + 1);
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumItem &&
          other.id == id &&
          other.name == name &&
          other.parentId == parentId &&
          other.itemCount == itemCount &&
          other.isSystem == isSystem &&
          other.isFavorites == isFavorites &&
          listEquals(other.children, children);

  @override
  int get hashCode => Object.hash(
    id,
    name,
    parentId,
    itemCount,
    isSystem,
    isFavorites,
    Object.hashAll(children),
  );
}
