import 'package:flutter/material.dart';
import 'package:quark/models/photo_album.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark/widgets/photos/album_name_dialog.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the package's [AlbumPickerSheet] for one photo, and adds it to or
/// takes it out of whichever album is tapped, until Done closes it. The
/// albums the photo is already in open checked, from its metadata (#3361).
///
/// Still service-coupled: it calls [AlbumService] itself. Moving that into a
/// controller is still to do; the album page it served is gone (#1916), and
/// the photos page opens it from a photo's menu in an album view.
class AddToAlbumSheetHost extends StatefulWidget {
  /// Creates the host for the photo at [relPath] on [deviceSerial].
  const AddToAlbumSheetHost({
    required this.deviceSerial,
    required this.relPath,
    this.onChanged,
    this.listAlbums = AlbumService.listAlbums,
    this.loadMemberAlbumIds = _memberAlbumIds,
    this.addPhotoToAlbum = AlbumService.addPhotoToAlbum,
    this.removePhotoFromAlbum = AlbumService.removePhotoFromAlbum,
    super.key,
  });

  /// Shows the sheet for the photo at [relPath] on [deviceSerial]. Answers
  /// whether any album changed, however the sheet was closed, so the caller
  /// can reload what counts its albums (#3361).
  static Future<bool> show(
    BuildContext context, {
    required String deviceSerial,
    required String relPath,
  }) async {
    var changed = false;
    await showQuarkSheet<void>(
      context,
      title: 'Add to album',
      builder: (_) => AddToAlbumSheetHost(
        deviceSerial: deviceSerial,
        relPath: relPath,
        onChanged: () => changed = true,
      ),
    );
    return changed;
  }

  /// The ids of the albums the photo is in, read from its metadata.
  static Future<Set<int>> _memberAlbumIds(
    String relPath, {
    String? serial,
  }) async => {
    for (final album in (await FilesService.getPhotoMetadata(
      relPath,
      serial: serial,
    )).albums)
      album.id,
  };

  /// The device the photo is stored on.
  final String deviceSerial;

  /// The photo's path on that device.
  final String relPath;

  /// Called after each add or removal the Quark took.
  final VoidCallback? onChanged;

  /// Lists the album tree.
  final Future<List<PhotoAlbum>> Function({bool tree}) listAlbums;

  /// The ids of the albums the photo at `relPath` is already in.
  final Future<Set<int>> Function(String relPath, {String? serial})
  loadMemberAlbumIds;

  /// Adds the photo to an album, answering whether it was new to it.
  final Future<bool> Function(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  })
  addPhotoToAlbum;

  /// Takes the photo out of an album.
  final Future<void> Function(
    int albumId, {
    required String deviceSerial,
    required String relPath,
  })
  removePhotoFromAlbum;

  @override
  State<AddToAlbumSheetHost> createState() => _AddToAlbumSheetHostState();
}

class _AddToAlbumSheetHostState extends State<AddToAlbumSheetHost> {
  List<AlbumItem> _albums = const [];
  final Set<int> _memberIds = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// The albums the photo is in, or none when they cannot be read.
  Future<Set<int>> _loadMembers() async {
    try {
      return await widget.loadMemberAlbumIds(
        widget.relPath,
        serial: widget.deviceSerial.isEmpty ? null : widget.deviceSerial,
      );
    } catch (_) {
      return const {};
    }
  }

  Future<void> _load() async {
    // Without its memberships the sheet still adds; the Quark's add is
    // idempotent, so an unchecked album the photo is in changes nothing.
    final members = _loadMembers();
    try {
      final albums = await widget.listAlbums(tree: true);
      final memberIds = await members;
      if (!mounted) return;
      setState(() {
        _albums = albums.toUserAlbumItems();
        _memberIds.addAll(memberIds);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _toggle(AlbumItem album) async {
    final isMember = _memberIds.contains(album.id);
    try {
      if (isMember) {
        await widget.removePhotoFromAlbum(
          album.id,
          deviceSerial: widget.deviceSerial,
          relPath: widget.relPath,
        );
      } else {
        await widget.addPhotoToAlbum(
          album.id,
          deviceSerial: widget.deviceSerial,
          relPath: widget.relPath,
        );
      }
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        if (isMember) {
          _memberIds.remove(album.id);
        } else {
          _memberIds.add(album.id);
        }
      });
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.message(e, 'update the album'));
    }
  }

  /// Makes an album and puts this photo straight into it (#2041).
  ///
  /// The sheet used to tell a user with no albums to go and create one in the
  /// Photos view, which meant losing the sheet, the selection and the photo
  /// they were looking at.
  Future<void> _createAndAdd() async {
    final name = await AlbumNameDialog.show(context, title: 'New album');
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final album = await AlbumService.createAlbum(name);
      await widget.addPhotoToAlbum(
        album.id,
        deviceSerial: widget.deviceSerial,
        relPath: widget.relPath,
      );
      widget.onChanged?.call();
      if (!mounted) return;
      setState(() {
        _albums = [
          ..._albums,
          AlbumItem(id: album.id, name: album.name, itemCount: 1),
        ];
        _memberIds.add(album.id);
      });
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.album(e, 'create the album'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlbumPickerSheet(
      albums: _albums,
      memberAlbumIds: _memberIds,
      keyPrefix: 'add_to_album',
      isLoading: _loading,
      onPicked: _toggle,
      onCreateAlbum: _createAndAdd,
      onDone: () => Navigator.of(context).pop(),
    );
  }
}
