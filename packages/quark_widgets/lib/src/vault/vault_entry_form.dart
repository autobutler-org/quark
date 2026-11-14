import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../core/quark_password_field.dart';
import '../models/vault_entry_item.dart';
import '../theme/quark_tokens.dart';

/// The fields that create or edit a saved login: name, website, username,
/// password (with show and generate), two-factor seed, notes and, when there
/// are folders, the folder. Save is disabled until there is a name.
///
/// What a save does, and where a generated password comes from, are the
/// caller's: [onSave] gets the fields as a [VaultEntryDraft], and
/// [onGeneratePassword] returns the password to put in the field. The fields
/// are [State] only because Flutter needs their controllers to live across
/// rebuilds; they start from [initial].
///
/// Key prefixes: `vault_entry_name`, `vault_entry_url`,
/// `vault_entry_username`, `vault_entry_password`, `vault_entry_totp`,
/// `vault_entry_notes` and `vault_entry_folder` on the fields,
/// `vault_entry_reveal` and `vault_entry_generate` on the password's
/// buttons, and `vault_entry_save` on the save button.
///
/// ```dart
/// VaultEntryForm(
///   initial: draft,
///   folders: controller.folderOptions,
///   isSaving: saving,
///   onGeneratePassword: controller.generate,
///   onSave: save,
/// );
/// ```
class VaultEntryForm extends StatefulWidget {
  /// Creates the form, filled from [initial].
  const VaultEntryForm({
    required this.onSave,
    required this.onGeneratePassword,
    this.initial = const VaultEntryDraft(),
    this.folders = const [],
    this.isSaving = false,
    super.key,
  });

  /// Called with the fields when save is tapped. Never with an empty name.
  final ValueChanged<VaultEntryDraft> onSave;

  /// Returns a new password for the password field, which is then shown.
  final String Function() onGeneratePassword;

  /// What the fields start with. Empty for a new login.
  final VaultEntryDraft initial;

  /// The folders the login can be filed in. Empty hides the folder field.
  final List<VaultFolderItem> folders;

  /// Whether a save is running. Holds the save button still.
  final bool isSaving;

  @override
  State<VaultEntryForm> createState() => _VaultEntryFormState();
}

class _VaultEntryFormState extends State<VaultEntryForm> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial.name,
  );
  late final TextEditingController _url = TextEditingController(
    text: widget.initial.url,
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.initial.username,
  );
  late final TextEditingController _password = TextEditingController(
    text: widget.initial.password,
  );
  late final TextEditingController _totp = TextEditingController(
    text: widget.initial.totpSecret,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.initial.notes,
  );
  late int? _folderId =
      widget.folders.any((f) => f.id == widget.initial.folderId)
      ? widget.initial.folderId
      : null;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _url,
      _username,
      _password,
      _totp,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSave => !widget.isSaving && _name.text.trim().isNotEmpty;

  void _save() {
    if (!_canSave) return;
    widget.onSave(
      VaultEntryDraft(
        name: _name.text.trim(),
        url: _url.text.trim(),
        username: _username.text,
        password: _password.text,
        notes: _notes.text,
        totpSecret: _totp.text.trim(),
        folderId: _folderId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final gap = SizedBox(height: tokens.spacingMd);
    return SingleChildScrollView(
      padding: EdgeInsets.all(tokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('vault_entry_name'),
            controller: _name,
            autofocus: widget.initial.name.isEmpty,
            decoration: const InputDecoration(
              labelText: 'Name',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
          gap,
          TextField(
            key: const ValueKey('vault_entry_url'),
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Website',
              border: OutlineInputBorder(),
            ),
          ),
          gap,
          TextField(
            key: const ValueKey('vault_entry_username'),
            controller: _username,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Username or email',
              border: OutlineInputBorder(),
            ),
          ),
          gap,
          QuarkPasswordField(
            key: const ValueKey('vault_entry_password'),
            controller: _password,
            labelText: 'Password',
            autofillHints: const [],
            visibilityKey: const ValueKey('vault_entry_reveal'),
            trailingBuilder: (context, reveal) => IconButton(
              key: const ValueKey('vault_entry_generate'),
              icon: const Icon(QuarkIcons.casino),
              tooltip: 'Generate password',
              onPressed: () {
                _password.text = widget.onGeneratePassword();
                reveal();
              },
            ),
          ),
          gap,
          TextField(
            key: const ValueKey('vault_entry_totp'),
            controller: _totp,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Two-factor secret',
              border: OutlineInputBorder(),
            ),
          ),
          gap,
          TextField(
            key: const ValueKey('vault_entry_notes'),
            controller: _notes,
            minLines: 2,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Notes',
              border: OutlineInputBorder(),
            ),
          ),
          if (widget.folders.isNotEmpty) ...[
            gap,
            DropdownButtonFormField<int?>(
              key: const ValueKey('vault_entry_folder'),
              initialValue: _folderId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Folder',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(child: Text('None')),
                for (final folder in widget.folders)
                  DropdownMenuItem(value: folder.id, child: Text(folder.name)),
              ],
              onChanged: (id) => setState(() => _folderId = id),
            ),
          ],
          SizedBox(height: tokens.spacingLg),
          FilledButton(
            key: const ValueKey('vault_entry_save'),
            onPressed: _canSave ? _save : null,
            child: widget.isSaving
                ? const QuarkLoader(size: 20)
                : const Text('Save'),
          ),
        ],
      ),
    );
  }
}
