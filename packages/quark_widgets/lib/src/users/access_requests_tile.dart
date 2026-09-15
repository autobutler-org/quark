import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// The switch that decides whether people can ask for an account from the
/// sign-in page.
///
/// Whether requests are on is the caller's state, [enabled] in and
/// [onChanged] out. While [isBusy] the switch holds still, so a second tap
/// cannot race the first.
///
/// Key prefixes: `access_requests_toggle` on the switch row.
///
/// ```dart
/// AccessRequestsTile(
///   enabled: controller.accessRequestsEnabled,
///   isBusy: controller.isSavingAccessRequests,
///   onChanged: controller.setAccessRequestsEnabled,
/// );
/// ```
class AccessRequestsTile extends StatelessWidget {
  /// Creates the switch showing [enabled].
  const AccessRequestsTile({
    required this.enabled,
    this.isBusy = false,
    this.onChanged,
    super.key,
  });

  /// Whether the sign-in page offers to request an account.
  final bool enabled;

  /// Whether a change is being saved. Disables the switch.
  final bool isBusy;

  /// Called with the new setting. Null disables the switch.
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);

    return SwitchListTile(
      key: const ValueKey('access_requests_toggle'),
      contentPadding: EdgeInsets.zero,
      title: const Text('Allow account requests'),
      subtitle: Text(
        'People can ask for an account from the sign-in page. An admin '
        'approves each one.',
        style: TextStyle(color: tokens.mutedForeground),
      ),
      value: enabled,
      onChanged: isBusy ? null : onChanged,
    );
  }
}
