import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme/reduce_motion.dart';
import 'quark_resizable_pane/quark_resize_handle.dart';

/// Which edge of its row a [QuarkResizablePane] sits on, which puts its
/// handle on the opposite, inner edge.
enum QuarkPaneEdge {
  /// The leading edge: the handle is on the pane's trailing side.
  start,

  /// The trailing edge: the handle is on the pane's leading side.
  end,
}

/// A sidebar pane on a wide window that the user resizes by dragging a handle
/// on its inner edge and collapses by dragging it below [minWidth], so every
/// sidebar in the app resizes and collapses the same way (#4294).
///
/// The width and the collapsed flag are the caller's state: [width] and
/// [isCollapsed] in, [onWidthChanged] and [onCollapsedChanged] out. The pane
/// holds nothing of its own; the handle keeps only its hover, focus and drag
/// visuals. A caller persists the two values if it wants them to survive a
/// reload, and puts its own show/hide button somewhere outside the pane,
/// because a collapsed pane renders nothing but its handle.
///
/// The handle replaces the hairline divider a fixed sidebar would draw: a
/// [handleWidth] hit target with a one-pixel line in `QuarkTokens.border`,
/// drawn in `QuarkTokens.primary` while hovered, focused or dragged. It shows
/// a resize cursor, and it is keyboard operable: the arrow keys resize by
/// [keyboardStep], Enter or Space toggles collapse, and screen readers get
/// [semanticLabel] with increase and decrease actions. A double tap resets
/// the width to [defaultWidth] and reopens a collapsed pane.
///
/// The rendered width is [width] clamped by [widthIn]: between [minWidth]
/// and [maxWidth], and never more than [maxFraction] of the window, so the
/// content keeps at least half of it. Collapsing and reopening slide; under
/// reduced motion they jump. Dragging never animates.
///
/// Wide layouts only: a phone layout shows a sidebar as a drawer or a sheet
/// and has no use for this.
///
/// Key prefixes: `resizable_pane_<id>` on the pane, `resizable_pane_handle_<id>`
/// on the handle and `resizable_pane_line_<id>` on its line.
///
/// ```dart
/// Row(
///   children: [
///     QuarkResizablePane(
///       id: 'albums',
///       semanticLabel: 'Resize albums',
///       width: prefs.width,
///       defaultWidth: 280,
///       isCollapsed: prefs.isCollapsed,
///       onWidthChanged: prefs.setWidth,
///       onCollapsedChanged: prefs.setCollapsed,
///       child: const AlbumSidebar(),
///     ),
///     const Expanded(child: PhotoGrid()),
///   ],
/// );
/// ```
class QuarkResizablePane extends StatelessWidget {
  /// Creates a resizable pane around [child].
  const QuarkResizablePane({
    required this.id,
    required this.semanticLabel,
    required this.width,
    required this.defaultWidth,
    required this.child,
    this.isCollapsed = false,
    this.edge = QuarkPaneEdge.start,
    this.minWidth = defaultMinWidth,
    this.maxWidth = defaultMaxWidth,
    this.maxFraction = defaultMaxFraction,
    this.onWidthChanged,
    this.onCollapsedChanged,
    super.key,
  });

  /// The narrowest a pane is dragged to before it collapses instead.
  static const double defaultMinWidth = 200;

  /// The widest a pane is dragged to.
  static const double defaultMaxWidth = 480;

  /// The share of the window one pane may take, so the content keeps the
  /// rest.
  static const double defaultMaxFraction = 0.5;

  /// The width of the handle's hit target, which is also the room it takes
  /// in the row.
  static const double handleWidth = 8;

  /// How far one arrow key press moves the handle.
  static const double keyboardStep = 16;

  /// How long collapsing and reopening take when motion is allowed.
  static const Duration collapseDuration = Duration(milliseconds: 200);

  /// The width a pane renders under [context] for a requested [width]:
  /// clamped between [minWidth] and the smaller of [maxWidth] and
  /// [maxFraction] of the window.
  ///
  /// For a layout that has to know the pane's width to size its content.
  static double widthIn(
    BuildContext context, {
    required double width,
    double minWidth = defaultMinWidth,
    double maxWidth = defaultMaxWidth,
    double maxFraction = defaultMaxFraction,
  }) {
    final window = MediaQuery.sizeOf(context).width;
    final cap = math.max(minWidth, math.min(maxWidth, window * maxFraction));
    return width.clamp(minWidth, cap);
  }

  /// Names the pane's keys, so two panes on one screen stay apart.
  final String id;

  /// What a screen reader announces for the handle, such as
  /// "Resize channels".
  final String semanticLabel;

  /// The pane's width when open, before [widthIn] clamps it.
  final double width;

  /// The width a double tap on the handle resets to.
  final double defaultWidth;

  /// The sidebar itself. It is laid out at the pane's full width even while
  /// the pane slides, so it does not reflow mid-animation.
  final Widget child;

  /// Whether the pane is collapsed to nothing but its handle.
  final bool isCollapsed;

  /// Which edge of the row the pane sits on.
  final QuarkPaneEdge edge;

  /// The narrowest open width; a drag below half of it collapses the pane.
  final double minWidth;

  /// The widest open width.
  final double maxWidth;

  /// The share of the window the pane may take.
  final double maxFraction;

  /// Fires with the new, clamped width while the handle is dragged or moved
  /// with the keyboard, and with [defaultWidth] on a double tap. Null makes
  /// the pane a fixed width.
  final ValueChanged<double>? onWidthChanged;

  /// Fires with true when the pane is dragged below its min width or toggled
  /// from the keyboard while open, and with false when it is dragged back
  /// out, toggled, or double tapped while collapsed. Null keeps it open.
  final ValueChanged<bool>? onCollapsedChanged;

  void _resize(double proposed) {
    if (proposed < minWidth / 2) {
      if (!isCollapsed) onCollapsedChanged?.call(true);
      return;
    }
    if (isCollapsed) onCollapsedChanged?.call(false);
    onWidthChanged?.call(proposed.clamp(minWidth, maxWidth));
  }

  void _reset() {
    if (isCollapsed) onCollapsedChanged?.call(false);
    onWidthChanged?.call(defaultWidth);
  }

  @override
  Widget build(BuildContext context) {
    final open = widthIn(
      context,
      width: width,
      minWidth: minWidth,
      maxWidth: maxWidth,
      maxFraction: maxFraction,
    );
    final ltr = Directionality.of(context) == TextDirection.ltr;
    final onCollapsedChanged = this.onCollapsedChanged;
    final pane = TweenAnimationBuilder<double>(
      tween: Tween(end: isCollapsed ? 0 : 1),
      duration: reduceMotionOf(context) ? Duration.zero : collapseDuration,
      curve: Curves.easeInOut,
      builder: (context, shown, child) => SizedBox(
        key: ValueKey('resizable_pane_$id'),
        width: open * shown,
        child: shown == 0
            ? null
            : ClipRect(
                child: OverflowBox(
                  alignment: edge == QuarkPaneEdge.start
                      ? AlignmentDirectional.centerEnd
                      : AlignmentDirectional.centerStart,
                  minWidth: open,
                  maxWidth: open,
                  child: child,
                ),
              ),
      ),
      child: child,
    );
    final handle = QuarkResizeHandle(
      id: id,
      semanticLabel: semanticLabel,
      width: isCollapsed ? 0 : open,
      // Moving right grows a start-edge pane in a left-to-right layout; every
      // other combination is the mirror image.
      growDirection: (edge == QuarkPaneEdge.start) == ltr ? 1 : -1,
      step: keyboardStep,
      onResize: onWidthChanged == null && onCollapsedChanged == null
          ? null
          : _resize,
      onToggle: onCollapsedChanged == null
          ? null
          : () => onCollapsedChanged(!isCollapsed),
      onReset: onWidthChanged == null ? null : _reset,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: edge == QuarkPaneEdge.start ? [pane, handle] : [handle, pane],
    );
  }
}
