import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';

/// The vault's lock screen when it can open with a face or fingerprint: a
/// headline, a sentence, the biometric button, and a way to type the
/// password instead.
///
/// Whether the face or fingerprint opened the vault is the caller's:
/// [isBusy] and [error] come in, and [onUnlock] and [onUsePassword] go out.
/// The caller words [unlockLabel] for the device ("Unlock with Face ID").
///
/// Key prefixes: `vault_biometric_unlock` on the biometric button and
/// `vault_biometric_unlock_password` on the password button.
///
/// ```dart
/// VaultBiometricUnlock(
///   title: 'Your vault is locked',
///   message: 'Open it with Face ID, or with the password you sign in with.',
///   unlockLabel: 'Unlock with Face ID',
///   isBusy: biometric.isBusy,
///   error: biometricError,
///   onUnlock: biometric.unlock,
///   onUsePassword: () => setState(() => usePassword = true),
/// );
/// ```
class VaultBiometricUnlock extends StatelessWidget {
  /// Creates the lock screen.
  const VaultBiometricUnlock({
    required this.title,
    required this.message,
    required this.unlockLabel,
    required this.onUnlock,
    required this.onUsePassword,
    this.passwordLabel = 'Use password instead',
    this.isBusy = false,
    this.error,
    super.key,
  });

  /// The headline.
  final String title;

  /// The sentence under it.
  final String message;

  /// The biometric button's label, naming the device's sensor.
  final String unlockLabel;

  /// Called when the biometric button is tapped.
  final VoidCallback onUnlock;

  /// The password button's label.
  final String passwordLabel;

  /// Called when the password button is tapped.
  final VoidCallback onUsePassword;

  /// Whether the biometric check is running. Holds both buttons still.
  final bool isBusy;

  /// Why the last check did not open the vault, composed by the caller.
  /// Null shows nothing.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(QuarkIcons.fingerprint, size: 48, color: tokens.primary),
              SizedBox(height: tokens.spacingMd),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              SizedBox(height: tokens.spacingSm),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(color: tokens.mutedForeground),
              ),
              if (error != null) ...[
                SizedBox(height: tokens.spacingMd),
                Text(
                  error,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: tokens.error),
                ),
              ],
              SizedBox(height: tokens.spacingLg),
              FilledButton.icon(
                key: const ValueKey('vault_biometric_unlock'),
                onPressed: isBusy ? null : onUnlock,
                icon: isBusy
                    ? const QuarkLoader(size: 20)
                    : const Icon(QuarkIcons.fingerprint),
                label: Text(unlockLabel),
              ),
              SizedBox(height: tokens.spacingSm),
              TextButton(
                key: const ValueKey('vault_biometric_unlock_password'),
                onPressed: isBusy ? null : onUsePassword,
                child: Text(passwordLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
