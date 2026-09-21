import 'package:flutter/material.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/widgets/vault/detail_row.dart';
import 'package:quark_icons/quark_icons.dart';

/// The read-only fields of a vault entry, with the password hidden until the user reveals it.
class EntryDetailView extends StatelessWidget {
  final VaultEntryDetail entry;
  final bool showPassword;
  final VoidCallback onToggleShowPassword;

  const EntryDetailView({
    super.key,
    required this.entry,
    required this.showPassword,
    required this.onToggleShowPassword,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailRow(label: 'Username', value: entry.username, copiable: true),
        DetailRow(
          label: 'Password',
          value: showPassword ? entry.password : '••••••••',
          copiable: true,
          copyValue: entry.password,
          trailing: IconButton(
            icon: Icon(
              showPassword ? QuarkIcons.visibility_off : QuarkIcons.visibility,
            ),
            onPressed: onToggleShowPassword,
          ),
        ),
        if (entry.url.isNotEmpty)
          DetailRow(label: 'URL', value: entry.url, copiable: true),
        if (entry.notes.isNotEmpty)
          DetailRow(label: 'Notes', value: entry.notes),
        if (entry.totpSecret.isNotEmpty)
          DetailRow(label: 'TOTP', value: '(configured)', copiable: false),
      ],
    );
  }
}
