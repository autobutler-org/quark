import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'remote_access_turn_off_dialog/remote_access_turn_off_consequence.dart';

/// Asks an admin to confirm turning remote access off for the whole
/// household, and says what that does: every device away from home loses
/// the Quark, home keeps working, and devices stay added for next time.
///
/// Show it with `showDialog` and pop from the callbacks; the dialog decides
/// nothing.
///
/// Key prefixes: `remote_access_turn_off_cancel`,
/// `remote_access_turn_off_confirm`.
///
/// ```dart
/// final confirmed = await showDialog<bool>(
///   context: context,
///   builder: (dialogContext) => RemoteAccessTurnOffDialog(
///     onCancel: () => Navigator.of(dialogContext).pop(false),
///     onConfirm: () => Navigator.of(dialogContext).pop(true),
///   ),
/// );
/// ```
class RemoteAccessTurnOffDialog extends StatelessWidget {
  /// Creates the dialog.
  const RemoteAccessTurnOffDialog({
    required this.onCancel,
    required this.onConfirm,
    super.key,
  });

  /// Keeps remote access on.
  final VoidCallback onCancel;

  /// Turns remote access off for everyone.
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return AlertDialog(
      // Title and content scroll together, so the buttons stay reachable at
      // a large text size on a short screen.
      scrollable: true,
      title: const Text('Turn off remote access for everyone?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        spacing: tokens.spacingMd,
        children: [
          RemoteAccessTurnOffConsequence(
            icon: QuarkIcons.cloud_off_outlined,
            color: tokens.error,
            text:
                "Every device away from home, including other people's "
                'phones, loses access to this Quark.',
          ),
          RemoteAccessTurnOffConsequence(
            icon: QuarkIcons.home_rounded,
            color: tokens.success,
            text: 'At home, everything keeps working as usual.',
          ),
          RemoteAccessTurnOffConsequence(
            icon: QuarkIcons.refresh,
            color: tokens.primary,
            text:
                "Devices you've added stay added. Turn it back on and they "
                'reconnect.',
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('remote_access_turn_off_cancel'),
          onPressed: onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('remote_access_turn_off_confirm'),
          style: FilledButton.styleFrom(
            backgroundColor: tokens.error,
            foregroundColor: tokens.errorForeground,
          ),
          onPressed: onConfirm,
          child: const Text('Turn off'),
        ),
      ],
    );
  }
}
