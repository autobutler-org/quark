import 'package:flutter/foundation.dart';

/// One photo as the widgets need it: an id, a name, and the flags that change
/// how its tile is drawn.
///
/// The package's own view of a photo, so no widget has to know where it is
/// stored. Controllers map their photo types into this at the edge and map
/// back by [id] when a callback comes out. The thumbnail itself is not here:
/// widgets ask a caller-supplied builder for it, because drawing one needs the
/// network or a device API the package does not depend on.
@immutable
class PhotoItem {
  /// Creates a photo.
  const PhotoItem({
    required this.id,
    required this.name,
    this.isRemote = true,
    this.hasLiveVideo = false,
    this.isFavorite = false,
  });

  /// The photo's stable identifier, unique across every source, and what
  /// selection sets and callbacks are matched on.
  final String id;

  /// The photo's display name.
  final String name;

  /// Whether the photo is stored on the server rather than only on this
  /// device. Only remote photos can be favorited.
  final bool isRemote;

  /// Whether the photo has a live video attached, which earns it a live badge.
  final bool hasLiveVideo;

  /// Whether the photo is a favorite, which earns it a star.
  final bool isFavorite;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoItem &&
          other.id == id &&
          other.name == name &&
          other.isRemote == isRemote &&
          other.hasLiveVideo == hasLiveVideo &&
          other.isFavorite == isFavorite;

  @override
  int get hashCode => Object.hash(id, name, isRemote, hasLiveVideo, isFavorite);
}
