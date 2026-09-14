import 'package:quark/models/photo_album.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Maps an app [PhotoAlbum] onto the package's [AlbumItem], subtree included.
///
/// The one place the two album types meet, so a renamed field lands here and
/// nowhere else.
extension PhotoAlbumToItem on PhotoAlbum {
  /// The package's view of this album.
  AlbumItem toAlbumItem() => AlbumItem(
    id: id,
    name: name,
    parentId: parentId,
    itemCount: itemCount,
    isSystem: isSystemAlbum,
    isFavorites: isFavorites,
    children: [for (final child in children) child.toAlbumItem()],
  );
}

/// The albums a photo can be put into, for an add-to-album picker.
extension PhotoAlbumsToPickerItems on Iterable<PhotoAlbum> {
  /// Every user album as the package's [AlbumItem]. System albums are left
  /// out: the Quark fills them itself and refuses edits to them (#992).
  List<AlbumItem> toUserAlbumItems() => [
    for (final album in this)
      if (!album.isSystemAlbum) album.toAlbumItem(),
  ];
}

/// Maps an app [StorageDevice] onto the package's [UploadTarget].
extension StorageDeviceToTarget on StorageDevice {
  /// The package's view of this device as somewhere to upload to.
  UploadTarget toUploadTarget() => UploadTarget(
    serial: serial,
    name: name,
    mountPoint: mountPoint,
    isInternal: isInternal,
  );
}
