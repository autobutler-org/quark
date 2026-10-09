import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// A custom tappable surface a keyboard can reach: it takes focus on Tab,
/// runs [onTap] on Enter or Space as well as on a tap, and draws a two-pixel
/// [QuarkTokens.primary] ring around [child] while it holds keyboard focus.
///
/// A bare `GestureDetector` answers a finger and a mouse and nothing else, so
/// a breadcrumb, a file type card or a photo was out of reach of anyone on a
/// keyboard, and nothing showed where focus was (#2604). Reach for this
/// wherever a `GestureDetector`'s `onTap` would otherwise make something
/// clickable. A stock button already does all of this; this is for the
/// surfaces that are not buttons to look at.
///
/// It adds no semantics of its own beyond the tap action and focus: the
/// caller still says what the surface is, with a `Semantics(button: true)`
/// around it. The ring is drawn over [child] without changing its layout, in
/// the shape of [borderRadius]. A null [onTap] leaves it out of the focus
/// order and inert, for a surface that is only sometimes a control.
///
/// Key prefixes: none of its own. The caller passes the `key` a test or a
/// `.probe` script reaches for.
///
/// ```dart
/// Semantics(
///   button: true,
///   child: QuarkTappable(
///     key: ValueKey('breadcrumb_segment_$index'),
///     onTap: () => onPathSelected(path),
///     child: Text(segment),
///   ),
/// );
/// ```
class QuarkTappable extends StatefulWidget {
  /// Creates a surface that runs [onTap] from a tap, Enter or Space.
  const QuarkTappable({
    required this.onTap,
    required this.child,
    this.borderRadius,
    this.mouseCursor,
    super.key,
  });

  /// Runs on a tap, or on Enter or Space while focused. Null takes the
  /// surface out of the focus order and leaves it inert.
  final VoidCallback? onTap;

  /// The shape of the focus ring, matching [child]'s corners. Null draws a
  /// square ring.
  final BorderRadius? borderRadius;

  /// The cursor over the surface. Null shows the click cursor while [onTap]
  /// is set and defers to what is underneath otherwise.
  final MouseCursor? mouseCursor;

  /// What the surface draws.
  final Widget child;

  @override
  State<QuarkTappable> createState() => _QuarkTappableState();
}

class _QuarkTappableState extends State<QuarkTappable> {
  bool _showFocus = false;

  void _activate() => widget.onTap?.call();

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final enabled = widget.onTap != null;
    return FocusableActionDetector(
      enabled: enabled,
      mouseCursor:
          widget.mouseCursor ??
          (enabled ? SystemMouseCursors.click : MouseCursor.defer),
      // Enter is an ActivateIntent on most platforms and a
      // ButtonActivateIntent on the web; a button answers both.
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) => _activate(),
        ),
        ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
          onInvoke: (_) => _activate(),
        ),
      },
      onShowFocusHighlight: (show) => setState(() => _showFocus = show),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: _showFocus && enabled
              ? BoxDecoration(
                  border: Border.all(color: tokens.primary, width: 2),
                  borderRadius: widget.borderRadius,
                )
              : const BoxDecoration(),
          child: widget.child,
        ),
      ),
    );
  }
}
