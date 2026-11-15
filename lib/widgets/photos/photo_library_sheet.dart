import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/photos_controller.dart';
import 'package:quark/widgets/photos/photo_library_nav.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The library picker a phone shows in a bottom sheet in place of the
/// sidebar (#4149): a [PhotoLibraryNav] that follows [controller] while it
/// is open and closes once the user picks All photos, a category or an
/// album.
///
/// The sheet is a route of its own, outside the page that owns
/// [controller], and a pick changes the URL, which hands the new album to the
/// controller while the page rebuilds. The sheet is still on screen then,
/// sliding away, so a change that arrives mid-build is rebuilt after the
/// frame instead of during it, where Flutter refuses it.
///
/// Key prefixes: none of its own; the sidebar's parts carry theirs.
///
/// ```dart
/// PhotoLibrarySheet.show(
///   context,
///   controller: controller,
///   onShowAlbum: showAlbum,
///   onCreateAlbum: createAlbum,
///   onAlbumMenu: showAlbumActions,
/// );
/// ```
class PhotoLibrarySheet extends StatefulWidget {
  /// Creates the sheet's body over [controller].
  const PhotoLibrarySheet({
    required this.controller,
    required this.onShowAlbum,
    required this.onCreateAlbum,
    required this.onAlbumMenu,
    super.key,
  });

  /// Shows the picker as a bottom sheet titled "Library".
  static Future<void> show(
    BuildContext context, {
    required PhotosController controller,
    required ValueChanged<int?> onShowAlbum,
    required VoidCallback onCreateAlbum,
    required void Function(AlbumItem album, Offset position) onAlbumMenu,
  }) => showQuarkSheet<void>(
    context,
    title: 'Library',
    // The sidebar pads itself.
    scrollable: false,
    builder: (_) => PhotoLibrarySheet(
      controller: controller,
      onShowAlbum: onShowAlbum,
      onCreateAlbum: onCreateAlbum,
      onAlbumMenu: onAlbumMenu,
    ),
  );

  /// Where the library and its albums come from.
  final PhotosController controller;

  /// Shows the album with this id, or All photos for null.
  final ValueChanged<int?> onShowAlbum;

  /// Starts making a new top-level album.
  final VoidCallback onCreateAlbum;

  /// Opens an album's menu at a global position.
  final void Function(AlbumItem album, Offset position) onAlbumMenu;

  @override
  State<PhotoLibrarySheet> createState() => _PhotoLibrarySheetState();
}

class _PhotoLibrarySheetState extends State<PhotoLibrarySheet> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(PhotoLibrarySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final binding = SchedulerBinding.instance;
    if (binding.schedulerPhase != SchedulerPhase.persistentCallbacks) {
      setState(() {});
      return;
    }
    binding.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: PhotoLibraryNav(
        controller: widget.controller,
        onShowAlbum: widget.onShowAlbum,
        onCreateAlbum: widget.onCreateAlbum,
        onAlbumMenu: widget.onAlbumMenu,
        onPicked: () => Navigator.of(context).pop(),
      ),
    );
  }
}
