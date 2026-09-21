import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

/// The good-news banner the credentials forms show above their fields.
///
/// The counterpart of [ErrorBanner]: same shape and the same live region, so
/// a screen reader announces "password updated" the way it announces a
/// failure. A reset used to end in silence on the sign-in form, which reads
/// as "did that work?" at the most anxious moment of the flow (#2029).
class NoticeBanner extends StatelessWidget {
  /// Creates a banner reading [message].
  const NoticeBanner({required this.message, super.key});

  /// The sentence to show. The caller owns the copy.
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('notice_banner'),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              QuarkIcons.check_circle_outline,
              color: theme.colorScheme.onPrimaryContainer,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
