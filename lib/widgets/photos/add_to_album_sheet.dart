import 'package:flutter/material.dart';
import 'package:quark/services/album_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget_items.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the package's [AddToAlbumSheet] for one photo, and adds it to or
/// takes it out of whichever album is tapped.
///
/// Still service-coupled: it calls [AlbumService] itself. Moving that into a
/// controller belongs to the album page's decoupling.
class AddToAlbumSheetHost extends StatefulWidget {
  /// Creates the host for the photo at [relPath] on [deviceSerial].
  const AddToAlbumSheetHost({
    required this.deviceSerial,
    required this.relPath,
    super.key,
  });

  /// Shows the sheet for the photo at [relPath] on [deviceSerial].
  static Future<void> show(
    BuildContext context, {
    required String deviceSerial,
    required String relPath,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(QuarkColors.radiusLg),
      ),
      builder: (_) =>
          AddToAlbumSheetHost(deviceSerial: deviceSerial, relPath: relPath),
    );
  }

  /// The device the photo is stored on.
  final String deviceSerial;

  /// The photo's path on that device.
  final String relPath;

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

  Future<void> _load() async {
    try {
      final albums = await AlbumService.listAlbums(tree: true);
      if (!mounted) return;
      setState(() {
        _albums = [for (final album in albums) album.toAlbumItem()];
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
        await AlbumService.removePhotoFromAlbum(
          album.id,
          deviceSerial: widget.deviceSerial,
          relPath: widget.relPath,
        );
      } else {
        await AlbumService.addPhotoToAlbum(
          album.id,
          deviceSerial: widget.deviceSerial,
          relPath: widget.relPath,
        );
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'update the album'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AddToAlbumSheet(
      albums: _albums,
      memberAlbumIds: _memberIds,
      isLoading: _loading,
      onToggle: _toggle,
    );
  }
}
