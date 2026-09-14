import 'package:quark/models/photo_album.dart';

/// The `?album=` value that names the album [id] on the Photos page (#1916).
///
/// Its name path — the names from the root down, joined with `/`, such as
/// `Trips/Japan` — when [resolveAlbumLink] would read that path back as this
/// very album. The Quark keeps album names unique among siblings, ignoring
/// case, and refuses a `/` in one, so a name path is the norm. Only an album
/// from before that rule — sharing its path with another, or with `/` in its
/// name — has a path that is ambiguous or unreadable, and is named by its id
/// instead.
///
/// An id is only a safe link while no album is literally named that number:
/// names win over ids, so in that rare case the id link opens the album with
/// that name, and nothing better can be written.
String albumLink(List<PhotoAlbum> tree, int id) {
  final path = _pathTo(tree, id);
  if (path != null) {
    final names = path.map((album) => album.name).join('/');
    if (resolveAlbumLink(tree, names)?.id == id) return names;
  }
  return '$id';
}

/// The album an `?album=` [value] names in [tree], or null for none.
///
/// [value] is read first as a name path (see [albumLink]): an exact match,
/// or, when nothing matches exactly, a case-insensitive one. A path that
/// matches more than one album matches none. Only then, and only when
/// [value] is a whole number, is it read as an album id — so an album named
/// `2024` wins over the album whose id is 2024.
PhotoAlbum? resolveAlbumLink(List<PhotoAlbum> tree, String value) {
  if (value.isEmpty) return null;
  final names = value.split('/');
  var matches = _matching(tree, names, (a, b) => a == b);
  if (matches.isEmpty) {
    matches = _matching(
      tree,
      names,
      (a, b) => a.toLowerCase() == b.toLowerCase(),
    );
  }
  if (matches.length == 1) return matches.single;
  if (matches.isNotEmpty || !RegExp(r'^-?\d+$').hasMatch(value)) return null;
  // Demo mode's sample albums have negative ids, hence the optional sign.
  return _pathTo(tree, int.parse(value))?.last;
}

/// Every album under [albums] whose name path is [names].
List<PhotoAlbum> _matching(
  List<PhotoAlbum> albums,
  List<String> names,
  bool Function(String, String) same,
) => [
  for (final album in albums)
    if (same(album.name, names.first))
      if (names.length == 1)
        album
      else
        ..._matching(album.children, names.sublist(1), same),
];

/// The albums from the root down to the album [id], or null when it is not
/// in [albums].
List<PhotoAlbum>? _pathTo(List<PhotoAlbum> albums, int id) {
  for (final album in albums) {
    if (album.id == id) return [album];
    final below = _pathTo(album.children, id);
    if (below != null) return [album, ...below];
  }
  return null;
}
