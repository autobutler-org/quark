import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:quark_icons/quark_icons.dart';

import 'quark_bar_icon_button.dart';

/// Keeps a toolbar one row high: a [child] wider than the space it is given
/// scrolls sideways instead of wrapping onto a second row (#2770).
///
/// However the user points, they can reach the far end:
///
/// - Touch: a drag scrolls it.
/// - Mouse wheel: a vertical wheel over the toolbar scrolls it sideways. The
///   wheel is only taken while the toolbar can still move that way, so the
///   page behind it scrolls again once the toolbar reaches its end.
/// - No wheel: once a mouse is connected, a chevron button sits over each
///   edge that has more behind it, and scrolls most of a viewport that way.
///   An edge with nothing behind it has no chevron. A touch-only device never
///   shows them, since they would only cover the controls a drag reaches.
///
/// The chevron's scroll is animated, and jumps instead under reduced motion
/// (`MediaQuery.disableAnimationsOf`, or the platform's
/// `accessibilityFeatures.reduceMotion`), read at each press.
///
/// A [child] that wraps, such as a `Wrap`, lays out on one line in here,
/// because the scroller gives it unbounded width.
///
/// Key prefixes: `toolbar_scroll_left` and `toolbar_scroll_right` on the
/// chevrons.
///
/// ```dart
/// QuarkToolbarScroller(
///   child: Row(children: [boldButton, italicButton, underlineButton]),
/// );
/// ```
class QuarkToolbarScroller extends StatefulWidget {
  /// Creates a one-row scroller around [child].
  const QuarkToolbarScroller({required this.child, super.key});

  /// How long a chevron press takes to scroll, outside reduced motion.
  static const Duration scrollDuration = Duration(milliseconds: 200);

  /// The share of the visible width one chevron press scrolls. Less than all
  /// of it, so the control at the edge stays on screen as a landmark.
  static const double scrollFraction = 0.8;

  /// The toolbar's controls, laid out with unbounded width.
  final Widget child;

  @override
  State<QuarkToolbarScroller> createState() => _QuarkToolbarScrollerState();
}

class _QuarkToolbarScrollerState extends State<QuarkToolbarScroller> {
  final ScrollController _controller = ScrollController();
  bool _canScrollBack = false;
  bool _canScrollForward = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _updateEdges(Notification notification) {
    if (notification is! ScrollMetricsNotification &&
        notification is! ScrollUpdateNotification) {
      return false;
    }
    final position = _controller.position;
    final back = position.extentBefore > precisionErrorTolerance;
    final forward = position.extentAfter > precisionErrorTolerance;
    if (back != _canScrollBack || forward != _canScrollForward) {
      setState(() {
        _canScrollBack = back;
        _canScrollForward = forward;
      });
    }
    return false;
  }

  double _clamped(double pixels) => pixels.clamp(
    _controller.position.minScrollExtent,
    _controller.position.maxScrollExtent,
  );

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final delta = event.scrollDelta;
    // A sideways wheel or trackpad swipe is the scroll view's own business.
    if (delta.dy == 0 || delta.dx.abs() > delta.dy.abs()) return;
    final position = _controller.position;
    if (_clamped(position.pixels + delta.dy) == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(
      event,
      (_) => position.pointerScroll(delta.dy),
    );
  }

  void _scrollBy(double direction) {
    final position = _controller.position;
    final target = _clamped(
      position.pixels +
          direction *
              position.viewportDimension *
              QuarkToolbarScroller.scrollFraction,
    );
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    if (reduceMotion) {
      position.jumpTo(target);
    } else {
      position.animateTo(
        target,
        duration: QuarkToolbarScroller.scrollDuration,
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mouseTracker = RendererBinding.instance.mouseTracker;
    final ltr = Directionality.of(context) == TextDirection.ltr;
    return ListenableBuilder(
      listenable: mouseTracker,
      builder: (context, scroller) => Stack(
        children: [
          scroller!,
          if (mouseTracker.mouseIsConnected)
            for (final left in const [true, false])
              // Scrolling back moves toward the left edge only when reading
              // left to right.
              if (left == ltr ? _canScrollBack : _canScrollForward)
                Positioned(
                  left: left ? 0 : null,
                  right: left ? null : 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: QuarkBarIconButton(
                      key: ValueKey(
                        left ? 'toolbar_scroll_left' : 'toolbar_scroll_right',
                      ),
                      icon: left
                          ? QuarkIcons.chevron_left
                          : QuarkIcons.chevron_right,
                      tooltip: left ? 'Scroll left' : 'Scroll right',
                      onPressed: () => _scrollBy(left == ltr ? -1 : 1),
                    ),
                  ),
                ),
        ],
      ),
      child: Listener(
        onPointerSignal: _onPointerSignal,
        child: NotificationListener<Notification>(
          onNotification: _updateEdges,
          child: SingleChildScrollView(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
