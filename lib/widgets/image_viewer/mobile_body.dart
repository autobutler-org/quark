import 'package:material_ui/material_ui.dart';
import 'package:quark/models/photo_metadata.dart';
import 'package:quark/widgets/image_viewer/metadata_drawer.dart';

/// The photo viewer at phone widths: the photo, with the metadata drawer
/// dragged up over it.
///
/// The drawer peeks at the date and place and opens, by its handle or its
/// rows, far enough to reach every section (#3359).
class MobileBody extends StatelessWidget {
  static const _minSize = 0.08;
  static const _peekSize = 0.28;
  static const _maxSize = 0.85;
  static const _snapSizes = [_minSize, _peekSize, _maxSize];

  /// How fast a handle drag has to end, in logical pixels per second, to
  /// carry the sheet on to the next snap rather than the nearest.
  static const _flingVelocity = 300.0;

  final Widget photoArea;
  final bool sidebarOpen;
  final DraggableScrollableController drawerController;
  final String name;
  final PhotoMetadata? metadata;
  final bool loading;
  final void Function(AlbumRef album) onAlbumTap;

  const MobileBody({
    super.key,
    required this.photoArea,
    required this.sidebarOpen,
    required this.drawerController,
    required this.name,
    required this.metadata,
    required this.loading,
    required this.onAlbumTap,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        photoArea,
        if (sidebarOpen)
          DraggableScrollableSheet(
            controller: drawerController,
            initialChildSize: _peekSize,
            minChildSize: _minSize,
            maxChildSize: _maxSize,
            snap: true,
            snapSizes: _snapSizes,
            builder: (context, scrollController) => MetadataDrawer(
              scrollController: scrollController,
              name: name,
              metadata: metadata,
              loading: loading,
              onAlbumTap: onAlbumTap,
              onHandleDrag: _dragBy,
              onHandleDragEnd: _settle,
            ),
          ),
      ],
    );
  }

  void _dragBy(double dy) {
    if (!drawerController.isAttached) return;
    final size = drawerController.size - drawerController.pixelsToSize(dy);
    drawerController.jumpTo(size.clamp(_minSize, _maxSize));
  }

  /// Snaps the sheet after a handle drag: to the next snap in the fling's
  /// direction, or to the nearest one when the handle was let go at rest.
  void _settle(double velocity) {
    if (!drawerController.isAttached) return;
    final size = drawerController.size;
    final double target;
    if (velocity <= -_flingVelocity) {
      target = _snapSizes.firstWhere((s) => s > size, orElse: () => _maxSize);
    } else if (velocity >= _flingVelocity) {
      target = _snapSizes.lastWhere((s) => s < size, orElse: () => _minSize);
    } else {
      target = _snapSizes.reduce(
        (a, b) => (a - size).abs() <= (b - size).abs() ? a : b,
      );
    }
    drawerController.animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }
}
