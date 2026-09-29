import 'package:quark/models/photo_album.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Orders albums by [sort]: names case-insensitively, dates by when the album
/// was created. Ties fall back to the id, so the order never shuffles between
/// reloads.
Comparator<PhotoAlbum> albumOrder(AlbumSort sort) => switch (sort) {
  AlbumSort.nameAsc => (a, b) => _byName(a, b),
  AlbumSort.nameDesc => (a, b) => _byName(b, a),
  AlbumSort.newest => (a, b) => _byCreated(b, a),
  AlbumSort.oldest => (a, b) => _byCreated(a, b),
};

int _byName(PhotoAlbum a, PhotoAlbum b) {
  final cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
  return cmp != 0 ? cmp : a.id.compareTo(b.id);
}

int _byCreated(PhotoAlbum a, PhotoAlbum b) {
  final cmp = a.createdAt.compareTo(b.createdAt);
  return cmp != 0 ? cmp : a.id.compareTo(b.id);
}
