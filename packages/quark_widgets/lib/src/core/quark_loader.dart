import 'package:flutter/widgets.dart';

import '../theme/quark_tokens.dart';
import 'quark_loader/quark_loader_painter.dart';

/// Quark's indeterminate loading indicator: three orbit rings, tilted 60
/// degrees apart, spinning inside a track circle, one full turn a second.
///
/// A drop-in for an indeterminate `CircularProgressIndicator`: the default
/// [size] matches its 36-pixel footprint, and stroke widths scale with [size].
/// The rings are drawn in `QuarkTokens.primary` and the track in
/// `QuarkTokens.border`.
///
/// Under reduced motion, when either `MediaQuery.disableAnimationsOf` (Android's
/// "Remove animations", the browser's `prefers-reduced-motion`) or the
/// platform's `accessibilityFeatures.reduceMotion` (iOS Reduce Motion) is set,
/// the rings hold a fixed tilt and the whole loader gently pulses its opacity
/// instead, so it never reads as a frozen frame.
///
/// Hidden from semantics, like the original; the surrounding UI says what is
/// loading. Emits no `ValueKey`s; it is not interactive.
///
/// Ported from the Atom loader in loading.dev (the `loading-dev` npm package,
/// 0.3.4), Copyright (c) 2026 Jakub Krehel, used under the MIT License.
///
/// ```dart
/// const Center(child: QuarkLoader());
/// ```
class QuarkLoader extends StatefulWidget {
  /// Creates a loader [size] pixels square.
  const QuarkLoader({this.size = 36.0, super.key});

  /// The width and height of the loader in logical pixels. Defaults to 36,
  /// the footprint of `CircularProgressIndicator`.
  final double size;

  @override
  State<QuarkLoader> createState() => _QuarkLoaderState();
}

class _QuarkLoaderState extends State<QuarkLoader>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _spin = Duration(milliseconds: 1000);
  static const _pulse = Duration(milliseconds: 1600);

  late final AnimationController _controller = AnimationController(vsync: this);
  bool? _reduceMotion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateMotion();
  }

  @override
  void didChangeAccessibilityFeatures() => setState(_updateMotion);

  void _updateMotion() {
    final reduce =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    if (reduce == _reduceMotion) return;
    _reduceMotion = reduce;
    _controller
      ..duration = reduce ? _pulse : _spin
      ..repeat(reverse: reduce);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final reduce = _reduceMotion!;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Opacity(
          opacity: reduce
              ? 1.0 - 0.6 * Curves.easeInOut.transform(_controller.value)
              : 1.0,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: QuarkLoaderPainter(
              progress: reduce ? null : _controller.value,
              ringColor: tokens.primary,
              trackColor: tokens.border,
            ),
          ),
        ),
      ),
    );
  }
}
