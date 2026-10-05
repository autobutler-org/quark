import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The find bar's counter — "3 of 12", "No results", "Invalid pattern" —
/// announced to a screen reader as it changes.
///
/// Key prefixes: `slide_find_status`.
class SlideFindStatus extends StatelessWidget {
  /// Shows [status].
  const SlideFindStatus({required this.status, super.key});

  /// What to say; empty shows nothing.
  final String status;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Text(
      status,
      key: const ValueKey('slide_find_status'),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: QuarkTokens.of(context).mutedForeground,
      ),
    ),
  );
}
