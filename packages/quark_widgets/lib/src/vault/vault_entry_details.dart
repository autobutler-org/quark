import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/copy_button.dart';
import '../core/quark_detail_row.dart';
import '../models/vault_entry_item.dart';
import '../theme/quark_tokens.dart';

/// A saved login, read-only: username, password (masked until revealed),
/// site, folder, whether it has a two-factor seed, and notes. Empty fields
/// other than the username and password are left out.
///
/// Copying goes out through [onCopy], since the package has no clipboard,
/// and revealing the password is the caller's [showPassword].
///
/// Key prefixes: `vault_detail_reveal` on the password's show button, and
/// `vault_detail_copy_<field>` on the copy buttons, where the field is
/// `username`, `password` or `url`.
///
/// ```dart
/// VaultEntryDetails(
///   entry: draft,
///   folderName: 'Work',
///   showPassword: showPassword,
///   onToggleShowPassword: () => setState(() => showPassword = !showPassword),
///   onCopy: (label, value) => copyToClipboard(label, value),
/// );
/// ```
class VaultEntryDetails extends StatelessWidget {
  /// Creates the details of [entry].
  const VaultEntryDetails({
    required this.entry,
    required this.showPassword,
    required this.onToggleShowPassword,
    required this.onCopy,
    this.folderName = '',
    super.key,
  });

  /// The login shown.
  final VaultEntryDraft entry;

  /// Whether the password is shown rather than masked.
  final bool showPassword;

  /// Called when the password's show or hide button is tapped.
  final VoidCallback onToggleShowPassword;

  /// Called with the field's label and value when its copy button is tapped.
  final void Function(String label, String value) onCopy;

  /// The name of the folder the login is filed in. Empty leaves it out.
  final String folderName;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    CopyButton copy(String field, String label, String value) => CopyButton(
      key: ValueKey('vault_detail_copy_$field'),
      text: value,
      iconSize: 18,
      onCopy: (text) async => onCopy(label, text),
    );
    return Padding(
      padding: EdgeInsets.all(tokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          QuarkDetailRow(
            selectable: true,
            label: 'Username',
            value: entry.username,
            actions: [copy('username', 'Username', entry.username)],
          ),
          QuarkDetailRow(
            selectable: true,
            label: 'Password',
            value: showPassword ? entry.password : '••••••••',
            actions: [
              IconButton(
                key: const ValueKey('vault_detail_reveal'),
                icon: Icon(
                  showPassword
                      ? QuarkIcons.visibility_off
                      : QuarkIcons.visibility,
                ),
                tooltip: showPassword ? 'Hide password' : 'Show password',
                onPressed: onToggleShowPassword,
              ),
              copy('password', 'Password', entry.password),
            ],
          ),
          if (entry.url.isNotEmpty)
            QuarkDetailRow(
              selectable: true,
              label: 'Website',
              value: entry.url,
              actions: [copy('url', 'Website', entry.url)],
            ),
          if (folderName.isNotEmpty)
            QuarkDetailRow(
              label: 'Folder',
              value: folderName,
              selectable: true,
            ),
          if (entry.totpSecret.isNotEmpty)
            const QuarkDetailRow(
              label: 'Two-factor',
              value: 'Set up',
              selectable: true,
            ),
          if (entry.notes.isNotEmpty)
            QuarkDetailRow(
              label: 'Notes',
              value: entry.notes,
              selectable: true,
            ),
        ],
      ),
    );
  }
}
