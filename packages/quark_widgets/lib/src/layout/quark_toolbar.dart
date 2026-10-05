import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';
import 'quark_toolbar_scroller.dart';

/// A row of actions that never overflows and is always one row high: actions
/// that do not fit scroll sideways inside a [QuarkToolbarScroller] (#2770).
///
/// A plain `Row` of buttons is fine until someone opens the app on a 360
/// pixel phone, at which point it throws a layout error and paints the yellow
/// stripes over the controls. Every bar in the app solved that separately.
/// This solves it once, so a new bar starts out narrow-safe.
///
/// The toolbar spaces its actions with the theme's small spacing token.
///
/// Key prefixes: none of its own beyond the scroller's `toolbar_scroll_left`
/// and `toolbar_scroll_right` chevrons. The keys a test or a `.probe` script
/// reaches for are the ones the actions carry.
///
/// ```dart
/// QuarkToolbar(
///   actions: [
///     IconButton(key: const ValueKey('files_refresh'), ...),
///     FilledButton(onPressed: upload, child: const Text('Upload')),
///   ],
/// );
/// ```
class QuarkToolbar extends StatelessWidget {
  /// Creates a toolbar of [actions].
  const QuarkToolbar({required this.actions, super.key});

  /// The controls, rendered in order along the main axis.
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return QuarkToolbarScroller(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: tokens.spacingSm,
        children: actions,
      ),
    );
  }
}
