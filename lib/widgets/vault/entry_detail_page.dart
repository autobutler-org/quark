import 'package:flutter/material.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/vault/entry_detail_view.dart';
import 'package:quark/widgets/vault/entry_edit_form.dart';
import 'package:quark_icons/quark_icons.dart';

/// The page for one vault entry, from which it can be edited or deleted.
class EntryDetailPage extends StatefulWidget {
  final VaultEntryDetail entry;
  final List<VaultFolder> folders;
  final Future<void> Function(Map<String, dynamic>) onSave;
  final Future<void> Function() onDelete;

  const EntryDetailPage({
    super.key,
    required this.entry,
    required this.folders,
    required this.onSave,
    required this.onDelete,
  });

  @override
  State<EntryDetailPage> createState() => _EntryDetailPageState();
}

class _EntryDetailPageState extends State<EntryDetailPage> {
  bool _showPassword = false;
  bool _editing = false;
  late TextEditingController _nameCtrl;
  late TextEditingController _urlCtrl;
  late TextEditingController _usernameCtrl;
  late TextEditingController _passwordCtrl;
  late TextEditingController _notesCtrl;
  int? _folderId;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.entry.name);
    _urlCtrl = TextEditingController(text: widget.entry.url);
    _usernameCtrl = TextEditingController(text: widget.entry.username);
    _passwordCtrl = TextEditingController(text: widget.entry.password);
    _notesCtrl = TextEditingController(text: widget.entry.notes);
    _folderId = widget.entry.folderId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit Entry' : widget.entry.name),
        actions: [
          if (!_editing)
            IconButton(
              icon: const Icon(QuarkIcons.edit),
              onPressed: () => setState(() => _editing = true),
            ),
          if (!_editing)
            IconButton(
              icon: const Icon(QuarkIcons.delete_outline),
              onPressed: _confirmDelete,
            ),
          if (_editing)
            TextButton(onPressed: _saveEntry, child: const Text('Save')),
          const AppThemeToggle(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _editing
            ? EntryEditForm(
                nameController: _nameCtrl,
                urlController: _urlCtrl,
                usernameController: _usernameCtrl,
                passwordController: _passwordCtrl,
                notesController: _notesCtrl,
                folders: widget.folders,
                folderId: _folderId,
                showPassword: _showPassword,
                onToggleShowPassword: () =>
                    setState(() => _showPassword = !_showPassword),
                onGeneratePassword: _generatePassword,
                onFolderChanged: (v) => setState(() => _folderId = v),
              )
            : EntryDetailView(
                entry: widget.entry,
                showPassword: _showPassword,
                onToggleShowPassword: () =>
                    setState(() => _showPassword = !_showPassword),
              ),
      ),
    );
  }

  Future<void> _generatePassword() async {
    try {
      final pw = await VaultService.generatePassword();
      _passwordCtrl.text = pw;
      setState(() => _showPassword = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'generate a password'))),
        );
      }
    }
  }

  Future<void> _saveEntry() async {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    try {
      await widget.onSave({
        'name': _nameCtrl.text,
        'url': _urlCtrl.text,
        'username': _usernameCtrl.text,
        'password': _passwordCtrl.text,
        'notes': _notesCtrl.text,
        'folderId': _folderId,
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'save the entry'))),
        );
      }
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await QuarkWidget.showDialog<bool>(
      context,
      builder: (ctx) => QuarkWidget.alertDialog(
        title: const Text('Delete entry?'),
        content: Text('Delete "${widget.entry.name}"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.onDelete();
      if (mounted) Navigator.pop(context, true);
    }
  }
}
