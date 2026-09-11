import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// A chevron fading down from the top edge, hinting that there is more above.
///
/// For a scroll view that starts scrolled past its first content, such as a
/// collapsed sidebar parked above a photo grid, where nothing else on screen
/// says the content is there. Never takes a pointer, so it can sit over
/// whatever it overlaps. The caller decides when to stop showing it.
///
/// Key prefix: `scroll_up_hint` on the hint itself.
///
/// ```dart
/// Stack(
///   children: [
///     scrollView,
///     if (showHint)
///       const Positioned(top: 0, left: 0, right: 0, child: ScrollUpHint()),
///   ],
/// );
/// ```
class ScrollUpHint extends StatelessWidget {
  /// Creates the hint.
  const ScrollUpHint({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return IgnorePointer(
      key: const ValueKey('scroll_up_hint'),
      child: Container(
        height: 32,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface.withValues(alpha: 0.7),
              colorScheme.surface.withValues(alpha: 0),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            QuarkIcons.keyboard_arrow_up_rounded,
            size: 20,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
