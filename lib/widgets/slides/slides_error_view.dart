import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the Slides list or the slide editor shows when it could not load:
/// the disconnected view when the Quark could not be reached (#1637), and
/// otherwise the `Errors` sentence for [action] with a retry button.
///
/// Key prefixes: `slides_retry` on the retry button.
class SlidesErrorView extends StatelessWidget {
  /// Shows [error], the thrown object, for the failed [action].
  const SlidesErrorView({
    required this.error,
    required this.action,
    required this.onRetry,
    super.key,
  });

  /// The thrown object, not its message.
  final Object error;

  /// What failed, as a bare verb phrase for `Errors.message`:
  /// `'load your presentations'`.
  final String action;

  /// Called when the retry button is tapped.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (isQuarkUnreachableError(error)) {
      return QuarkDisconnectedView(
        hostAddress: AppSettings.instance.activeHost,
        onRetry: onRetry,
        onManageHosts: () =>
            context.go(AppRoutes.settingsTab(SettingsTab.general)),
      );
    }
    return EmptyStateWidget(
      icon: QuarkIcons.error_outline,
      headline: Errors.message(error, action),
      action: FilledButton(
        key: const ValueKey('slides_retry'),
        onPressed: onRetry,
        child: const Text('Retry'),
      ),
    );
  }
}
