import 'package:material_ui/material_ui.dart';

import 'photo_grid_drag_selection.dart';

/// Wraps one tile of a `PhotoGrid` for its [PhotoGridDragSelection]: hands
/// it the pointers that go down on the tile, and tags the tile so the drag
/// can find it under the pointer (#4171).
///
/// It only listens. It takes part in no gesture arena, so the tile's taps
/// and long presses and the scroll view's swipes behave as they would
/// without it.
class PhotoGridDragTarget extends StatelessWidget {
  /// Wraps [child], the tile at [index], for [selection].
  const PhotoGridDragTarget({
    required this.selection,
    required this.index,
    required this.child,
    super.key,
  });

  /// The drag selection of the grid the tile belongs to.
  final PhotoGridDragSelection selection;

  /// The tile's index into the grid's photos.
  final int index;

  /// The tile.
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (event) => selection.pointerDown(index, event),
    child: MetaData(
      metaData: PhotoGridDragTag(selection, index),
      behavior: HitTestBehavior.opaque,
      child: child,
    ),
  );
}
