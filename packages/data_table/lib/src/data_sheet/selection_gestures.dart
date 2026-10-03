import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// The grid position under a pointer, or `null` when the pointer is not over
/// a cell.
typedef CellHitTest = ({int row, int col})? Function(Offset globalPosition);

/// Turns pointer drags over the grid body into range selection without
/// stealing scroll gestures.
///
/// A mouse selects by pressing and dragging, since a mouse never scrolls by
/// dragging. A finger or stylus has to long-press first: a quick swipe still
/// reaches the scroll view underneath, and only a press held in place starts
/// a range, which then follows the finger.
///
/// Pass `enabled: false` while a cell is being edited so drags reach the text
/// field. The detectors stay in the tree either way, so toggling it never
/// rebuilds [child]'s state.
class DataSheetSelectionGestures extends StatelessWidget {
  /// Whether drags select. When false every gesture passes through.
  final bool enabled;

  /// Maps a global pointer position to the cell beneath it.
  final CellHitTest cellAt;

  /// Called with the cell a drag or long-press started on.
  final void Function(int row, int col) onRangeStart;

  /// Called with the cell under the pointer as the drag moves.
  final void Function(int row, int col) onRangeExtend;

  /// The grid body the gestures cover.
  final Widget child;

  /// Creates the gesture layer over [child].
  const DataSheetSelectionGestures({
    super.key,
    required this.enabled,
    required this.cellAt,
    required this.onRangeStart,
    required this.onRangeExtend,
    required this.child,
  });

  void _start(Offset position) {
    final hit = cellAt(position);
    if (hit != null) onRangeStart(hit.row, hit.col);
  }

  void _extend(Offset position) {
    final hit = cellAt(position);
    if (hit != null) onRangeExtend(hit.row, hit.col);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      supportedDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      },
      onLongPressStart: enabled ? (d) => _start(d.globalPosition) : null,
      onLongPressMoveUpdate: enabled ? (d) => _extend(d.globalPosition) : null,
      child: GestureDetector(
        supportedDevices: const {PointerDeviceKind.mouse},
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: enabled ? (d) => _start(d.globalPosition) : null,
        onPanUpdate: enabled ? (d) => _extend(d.globalPosition) : null,
        child: child,
      ),
    );
  }
}
