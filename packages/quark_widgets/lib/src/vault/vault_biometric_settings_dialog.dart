import 'package:flutter/material.dart';

import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';

/// The setting that opens the vault with a face or fingerprint on this
/// device: a switch, and what turning it on means, said before it is on.
///
/// The switch only reports: [onChanged] fires with the wanted value, and
/// [value], [isBusy] and [error] come back from the caller once the device
/// has stored or deleted the key. It does not close itself; [onClose]
/// fires and the caller pops it. The copy scrolls when the window is short.
///
/// Key prefixes: `vault_biometric_switch` on the switch and
/// `vault_biometric_settings_close` on the close button.
///
/// ```dart
/// VaultBiometricSettingsDialog(
///   title: 'Unlock with Face ID',
///   explanation: 'Anyone who can pass Face ID on this device can open your vault.',
///   value: biometric.enabled,
///   isBusy: biometric.isBusy,
///   onChanged: (on) => on ? biometric.enable() : biometric.disable(),
///   onClose: () => Navigator.of(context).pop(),
/// );
/// ```
class VaultBiometricSettingsDialog extends StatelessWidget {
  /// Creates the setting.
  const VaultBiometricSettingsDialog({
    required this.title,
    required this.explanation,
    required this.value,
    required this.onChanged,
    required this.onClose,
    this.isBusy = false,
    this.error,
    super.key,
  });

  /// The setting's name, which is also the switch's label.
  final String title;

  /// What turning it on means: where the key is kept, who can open the
  /// vault, and what turns it off.
  final String explanation;

  /// Whether it is on.
  final bool value;

  /// Called with the value the user asked for.
  final ValueChanged<bool> onChanged;

  /// Called when the close button is tapped.
  final VoidCallback onClose;

  /// Whether the device is storing or deleting the key. Holds the switch
  /// still and shows a loader beside it.
  final bool isBusy;

  /// Why the last change did not go through, composed by the caller. Null
  /// shows nothing.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    return AlertDialog(
      scrollable: true,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(explanation, style: TextStyle(color: tokens.mutedForeground)),
          SizedBox(height: tokens.spacingMd),
          SwitchListTile(
            key: const ValueKey('vault_biometric_switch'),
            contentPadding: EdgeInsets.zero,
            title: Text(title),
            secondary: isBusy ? const QuarkLoader(size: 20) : null,
            value: value,
            onChanged: isBusy ? null : onChanged,
          ),
          if (error != null) ...[
            SizedBox(height: tokens.spacingSm),
            Text(error, style: TextStyle(color: tokens.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('vault_biometric_settings_close'),
          onPressed: onClose,
          child: const Text('Close'),
        ),
      ],
    );
  }
}
