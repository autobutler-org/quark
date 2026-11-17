import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../theme/quark_tokens.dart';
import '../quark_resizable_pane.dart';

/// The drag handle on a `QuarkResizablePane`'s inner edge: a hit target
/// with a one-pixel line down its middle, a resize cursor, and the arrow,
/// Enter and Space keys. A screen reader gets increase and decrease actions
/// but no tap, so the thin handle is not a tap target.
///
/// It turns a drag or a key press into a proposed width for the pane and
/// leaves clamping and collapsing to the pane. Its only state is the hover,
/// focus and drag visuals, and the width the current drag started from.
///
/// Key prefixes: `resizable_pane_handle_<id>` on the handle and
/// `resizable_pane_line_<id>` on its line.
class QuarkResizeHandle extends StatefulWidget {
  /// Creates the handle for the pane named [id].
  const QuarkResizeHandle({
    required this.id,
    required this.semanticLabel,
    required this.width,
    required this.growDirection,
    required this.step,
    this.onResize,
    this.onToggle,
    this.onReset,
    super.key,
  });

  /// The pane's id, for the keys.
  final String id;

  /// What a screen reader announces for the handle.
  final String semanticLabel;

  /// The pane's current width, zero when collapsed.
  final double width;

  /// 1 when moving right grows the pane, -1 when moving left does.
  final double growDirection;

  /// How far one arrow key press moves the handle.
  final double step;

  /// Fires with the width the pane would have after a drag or key press.
  /// Null makes the handle inert.
  final ValueChanged<double>? onResize;

  /// Fires on Enter or Space, to collapse or reopen the pane.
  final VoidCallback? onToggle;

  /// Fires on a double tap, to reset the pane's width.
  final VoidCallback? onReset;

  @override
  State<QuarkResizeHandle> createState() => _QuarkResizeHandleState();
}

class _QuarkResizeHandleState extends State<QuarkResizeHandle> {
  bool _hovered = false;
  bool _focused = false;
  double? _dragWidth;

  void _nudge(double steps) =>
      widget.onResize?.call(widget.width + steps * widget.step);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight) {
      _nudge(widget.growDirection);
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _nudge(-widget.growDirection);
    } else if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space)) {
      widget.onToggle?.call();
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final onResize = widget.onResize;
    final active = _hovered || _focused || _dragWidth != null;
    return Semantics(
      label: widget.semanticLabel,
      value: widget.width == 0 ? 'Collapsed' : '${widget.width.round()}',
      increasedValue: '${(widget.width + widget.step).round()}',
      decreasedValue:
          '${(widget.width - widget.step).clamp(0, double.infinity).round()}',
      onIncrease: onResize == null ? null : () => _nudge(1),
      onDecrease: onResize == null ? null : () => _nudge(-1),
      // No tap action: a screen reader reaches the handle as an adjustable,
      // like a slider, and a tappable node this thin fails the 48dp tap
      // target guideline. Enter and Space still toggle from a keyboard, and
      // the caller's own show/hide button collapses the pane for everyone.
      child: Focus(
        canRequestFocus: onResize != null,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _onKey,
        child: MouseRegion(
          cursor: onResize == null
              ? MouseCursor.defer
              : SystemMouseCursors.resizeColumn,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            key: ValueKey('resizable_pane_handle_${widget.id}'),
            behavior: HitTestBehavior.opaque,
            dragStartBehavior: DragStartBehavior.down,
            onDoubleTap: widget.onReset,
            onHorizontalDragStart: onResize == null
                ? null
                : (_) => setState(() => _dragWidth = widget.width),
            onHorizontalDragUpdate: onResize == null
                ? null
                : (details) {
                    final next =
                        _dragWidth! + details.delta.dx * widget.growDirection;
                    _dragWidth = next;
                    onResize(next);
                  },
            onHorizontalDragEnd: onResize == null
                ? null
                : (_) => setState(() => _dragWidth = null),
            child: SizedBox(
              width: QuarkResizablePane.handleWidth,
              child: Center(
                child: SizedBox(
                  width: active && onResize != null ? 2 : 1,
                  child: ColoredBox(
                    key: ValueKey('resizable_pane_line_${widget.id}'),
                    color: active && onResize != null
                        ? tokens.primary
                        : tokens.border,
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
