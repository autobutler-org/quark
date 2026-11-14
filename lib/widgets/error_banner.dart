import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What an [ErrorBanner] is telling the user, which picks its icon and color.
enum ErrorBannerTone {
  /// Something failed. Error container, announced to screen readers.
  error(QuarkIcons.error_outline),

  /// Something worked, like a reset password. Primary container, announced
  /// the way a failure is, so success is not met with silence (#2029).
  notice(QuarkIcons.check_circle_outline),

  /// What an action is about to cost, like data left behind by a reset. The
  /// warning token's tint.
  warning(QuarkIcons.warning_amber),

  /// Why the user is here, like the terms page naming its Quark. Secondary
  /// container.
  info(QuarkIcons.info_outline);

  const ErrorBannerTone(this.icon);

  /// The glyph leading the row.
  final IconData icon;
}

/// One message in a tinted row: an icon and the sentence beside it.
///
/// The credentials forms show it above their fields, and [tone] reuses the
/// same row for good news, warnings, and context, so every banner in the app
/// has one shape. The error and notice tones are live regions, so a screen
/// reader reads them out when they appear.
class ErrorBanner extends StatelessWidget {
  /// Creates a banner reading [message] in [tone].
  const ErrorBanner({
    super.key,
    required this.message,
    this.tone = ErrorBannerTone.error,
  });

  /// The sentence to show. The caller owns the copy.
  final String message;

  /// Which kind of message this is. Defaults to an error.
  final ErrorBannerTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = QuarkTokens.of(context);
    final (background, foreground, iconColor) = switch (tone) {
      ErrorBannerTone.error => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        colorScheme.onErrorContainer,
      ),
      ErrorBannerTone.notice => (
        colorScheme.primaryContainer,
        colorScheme.onPrimaryContainer,
        colorScheme.onPrimaryContainer,
      ),
      ErrorBannerTone.warning => (
        tokens.warning.withValues(alpha: 0.15),
        colorScheme.onSurface,
        tokens.warning,
      ),
      ErrorBannerTone.info => (
        colorScheme.secondaryContainer,
        colorScheme.onSecondaryContainer,
        colorScheme.onSecondaryContainer,
      ),
    };
    return Semantics(
      liveRegion:
          tone == ErrorBannerTone.error || tone == ErrorBannerTone.notice,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(tone.icon, color: iconColor, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(color: foreground),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
