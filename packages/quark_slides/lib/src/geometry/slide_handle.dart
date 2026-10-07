/// A grip on a selected element's frame: one of the eight resize handles
/// around its edge, or the rotate handle above its top edge.
///
/// [dx] and [dy] place the handle on the frame before rotation: -1 is the left or
/// top edge, 1 the right or bottom edge, 0 the middle. A resize handle moves
/// the edges it sits on and keeps the opposite ones still. The canvas keys
/// each handle's widget [keyName], `slide_handle_<id>`, so a Probe script can
/// write `drag #slide_handle_bottom_right`.
enum SlideHandle {
  /// The top-left corner.
  topLeft(-1, -1, 'top_left'),

  /// The middle of the top edge.
  top(0, -1, 'top'),

  /// The top-right corner.
  topRight(1, -1, 'top_right'),

  /// The middle of the right edge.
  right(1, 0, 'right'),

  /// The bottom-right corner.
  bottomRight(1, 1, 'bottom_right'),

  /// The middle of the bottom edge.
  bottom(0, 1, 'bottom'),

  /// The bottom-left corner.
  bottomLeft(-1, 1, 'bottom_left'),

  /// The middle of the left edge.
  left(-1, 0, 'left'),

  /// The rotate handle, above the middle of the top edge.
  rotate(0, -1, 'rotate');

  const SlideHandle(this.dx, this.dy, this.id);

  /// -1 for the left edge, 1 for the right, 0 for neither.
  final int dx;

  /// -1 for the top edge, 1 for the bottom, 0 for neither.
  final int dy;

  /// The snake-case name used in [keyName].
  final String id;

  /// The eight resize handles, clockwise from the top-left corner.
  static const resizeHandles = [
    topLeft,
    top,
    topRight,
    right,
    bottomRight,
    bottom,
    bottomLeft,
    left,
  ];

  /// Whether the handle resizes, as every handle but [rotate] does.
  bool get isResize => this != rotate;

  /// Whether the handle is a corner, which can resize keeping the aspect
  /// ratio.
  bool get isCorner => dx != 0 && dy != 0;

  /// The `ValueKey` value of the handle's widget: `slide_handle_<id>`.
  String get keyName => 'slide_handle_$id';
}
