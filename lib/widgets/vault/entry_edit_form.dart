import 'package:flutter/material.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark_icons/quark_icons.dart';

/// The fields for creating or editing a vault entry: name, URL, username, password with a generator, notes, and
/// folder.
class EntryEditForm extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController urlController;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final TextEditingController notesController;
  final List<VaultFolder> folders;
  final int? folderId;
  final bool showPassword;
  final VoidCallback onToggleShowPassword;
  final VoidCallback onGeneratePassword;
  final ValueChanged<int?> onFolderChanged;

  const EntryEditForm({
    super.key,
    required this.nameController,
    required this.urlController,
    required this.usernameController,
    required this.passwordController,
    required this.notesController,
    required this.folders,
    required this.folderId,
    required this.showPassword,
    required this.onToggleShowPassword,
    required this.onGeneratePassword,
    required this.onFolderChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: urlController,
          decoration: const InputDecoration(
            labelText: 'URL',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: usernameController,
          decoration: const InputDecoration(
            labelText: 'Username',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: passwordController,
          obscureText: !showPassword,
          decoration: InputDecoration(
            labelText: 'Password',
            border: const OutlineInputBorder(),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    showPassword
                        ? QuarkIcons.visibility_off
                        : QuarkIcons.visibility,
                  ),
                  onPressed: onToggleShowPassword,
                ),
                IconButton(
                  icon: const Icon(QuarkIcons.casino),
                  tooltip: 'Generate password',
                  onPressed: onGeneratePassword,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: notesController,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Notes',
            border: OutlineInputBorder(),
          ),
        ),
        if (folders.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: folderId,
            decoration: const InputDecoration(
              labelText: 'Folder',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              ...folders.map(
                (f) => DropdownMenuItem(value: f.id, child: Text(f.name)),
              ),
            ],
            onChanged: onFolderChanged,
          ),
        ],
      ],
    );
  }
}
