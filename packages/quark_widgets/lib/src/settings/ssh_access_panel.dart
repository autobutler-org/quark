import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/ssh_key_item.dart';
import '../theme/quark_tokens.dart';
import 'ssh_access_panel/ssh_key_row.dart';

/// SSH access to the Quark: an on/off switch, the public keys allowed to sign
/// in, and the login password's set and clear actions.
///
/// When [unavailableReason] is set, SSH access can't be managed on this
/// Quark, and the reason (with its fix) replaces every control. A spinner
/// replaces them while [isLoading]. While [isWorking] every control is
/// disabled. The panel decides nothing: the caller confirms before turning
/// SSH on, prompts for keys and passwords, and composes [error].
///
/// Key prefixes: `ssh_unavailable`, `ssh_enabled_switch`, `ssh_add_key`,
/// `ssh_set_password`, `ssh_clear_password`, and per key `ssh_key_<fingerprint>`
/// and `ssh_remove_key_<fingerprint>`.
///
/// ```dart
/// SshAccessPanel(
///   enabled: status.enabled,
///   keys: keys,
///   onEnabledChanged: controller.setEnabled,
///   onAddKey: promptForKey,
///   onRemoveKey: controller.removeKey,
///   onSetPassword: promptForPassword,
///   onClearPassword: controller.clearPassword,
/// );
/// ```
class SshAccessPanel extends StatelessWidget {
  /// Creates the panel.
  const SshAccessPanel({
    this.enabled = false,
    this.keys = const [],
    this.isLoading = false,
    this.isWorking = false,
    this.error,
    this.unavailableReason,
    this.onEnabledChanged,
    this.onAddKey,
    this.onRemoveKey,
    this.onSetPassword,
    this.onClearPassword,
    super.key,
  });

  /// Whether SSH access is on.
  final bool enabled;

  /// The keys allowed to sign in, in order.
  final List<SshKeyItem> keys;

  /// Whether the status is being fetched. Shows a spinner instead of controls.
  final bool isLoading;

  /// Whether a change is in flight. Disables every control.
  final bool isWorking;

  /// A sentence the caller composed about the last failure, or null.
  final String? error;

  /// Why SSH access can't be managed here, with its fix, or null when it can.
  final String? unavailableReason;

  /// Called with the switch's new value.
  final ValueChanged<bool>? onEnabledChanged;

  /// Called when Add key is tapped.
  final VoidCallback? onAddKey;

  /// Called with a key's fingerprint when its remove button is tapped.
  final ValueChanged<String>? onRemoveKey;

  /// Called when Set password is tapped.
  final VoidCallback? onSetPassword;

  /// Called when Clear password is tapped.
  final VoidCallback? onClearPassword;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final reason = unavailableReason;
    final errorText = error;
    final active = !isWorking;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: const Center(child: QuarkLoader()),
      );
    }

    if (reason != null) {
      return ListTile(
        key: const ValueKey('ssh_unavailable'),
        leading: const Icon(QuarkIcons.info_outline),
        title: const Text('SSH access'),
        subtitle: Text(reason),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        SwitchListTile(
          key: const ValueKey('ssh_enabled_switch'),
          title: const Text('SSH access'),
          subtitle: const Text(
            'Sign in to this Quark as quark over SSH, on port 22',
          ),
          value: enabled,
          onChanged: active ? onEnabledChanged : null,
        ),
        if (errorText != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.spacingMd),
            child: Text(errorText, style: TextStyle(color: tokens.error)),
          ),
        Padding(
          padding: EdgeInsets.all(tokens.spacingMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Allowed keys', style: theme.textTheme.titleSmall),
              if (keys.isEmpty)
                Padding(
                  padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
                  child: Text(
                    'No keys yet. Add a public key, such as the contents of '
                    'id_ed25519.pub.',
                    style: TextStyle(color: tokens.mutedForeground),
                  ),
                ),
              for (final key in keys)
                SshKeyRow(item: key, onRemove: active ? onRemoveKey : null),
              Wrap(
                spacing: tokens.spacingSm,
                runSpacing: tokens.spacingSm,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('ssh_add_key'),
                    onPressed: active ? onAddKey : null,
                    icon: const Icon(QuarkIcons.add),
                    label: const Text('Add key'),
                  ),
                ],
              ),
              SizedBox(height: tokens.spacingLg),
              Text('Login password', style: theme.textTheme.titleSmall),
              Padding(
                padding: EdgeInsets.symmetric(vertical: tokens.spacingSm),
                child: Text(
                  'Optional. Keys always work; a password works only once one '
                  'is set. Quark does not store it.',
                  style: TextStyle(color: tokens.mutedForeground),
                ),
              ),
              Wrap(
                spacing: tokens.spacingSm,
                runSpacing: tokens.spacingSm,
                children: [
                  OutlinedButton.icon(
                    key: const ValueKey('ssh_set_password'),
                    onPressed: active ? onSetPassword : null,
                    icon: const Icon(QuarkIcons.lock_outline),
                    label: const Text('Set password'),
                  ),
                  TextButton(
                    key: const ValueKey('ssh_clear_password'),
                    onPressed: active ? onClearPassword : null,
                    child: const Text('Clear password'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
