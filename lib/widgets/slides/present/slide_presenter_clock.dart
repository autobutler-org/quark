import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// How long the presentation has been running, as `mm:ss` — `h:mm:ss` past
/// the hour — in the presenter view (#1165).
///
/// It listens to [elapsed] itself, so the tick each second rebuilds this
/// text and nothing else.
///
/// Key prefixes: `slide_presenter_clock` on the text.
///
/// ```dart
/// SlidePresenterClock(elapsed: c.elapsed);
/// ```
class SlidePresenterClock extends StatelessWidget {
  /// Shows [elapsed].
  const SlidePresenterClock({required this.elapsed, super.key});

  /// Time since the presentation started.
  final ValueListenable<Duration> elapsed;

  /// [time] as the clock reads it: `04:07`, or `1:04:07` past the hour.
  static String format(Duration time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final minutes = two(time.inMinutes.remainder(60));
    final seconds = two(time.inSeconds.remainder(60));
    return time.inHours > 0
        ? '${time.inHours}:$minutes:$seconds'
        : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return ValueListenableBuilder(
      valueListenable: elapsed,
      builder: (context, time, _) => Semantics(
        label: 'Time elapsed',
        child: Text(
          format(time),
          key: const ValueKey('slide_presenter_clock'),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            color: tokens.foreground,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
