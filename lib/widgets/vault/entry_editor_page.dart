import 'package:flutter/material.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';

/// The page for creating a new vault entry.
class EntryEditorPage extends StatefulWidget {
  final List<VaultFolder> folders;

  const EntryEditorPage({super.key, required this.folders});

  @override
  State<EntryEditorPage> createState() => _EntryEditorPageState();
}

class _EntryEditorPageState extends State<EntryEditorPage> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  int? _folderId;
  bool _showPassword = false;
  bool _saving = false;

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
        title: const Text('New Entry'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
          const AppThemeToggle(),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _urlCtrl,
              decoration: const InputDecoration(
                labelText: 'URL',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameCtrl,
              decoration: const InputDecoration(
                labelText: 'Username / Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordCtrl,
              obscureText: !_showPassword,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _showPassword
                            ? QuarkIcons.visibility_off
                            : QuarkIcons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                    IconButton(
                      icon: const Icon(QuarkIcons.casino),
                      tooltip: 'Generate password',
                      onPressed: _generatePassword,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
            ),
            if (widget.folders.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: _folderId,
                decoration: const InputDecoration(
                  labelText: 'Folder',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ...widget.folders.map(
                    (f) => DropdownMenuItem(value: f.id, child: Text(f.name)),
                  ),
                ],
                onChanged: (v) => setState(() => _folderId = v),
              ),
            ],
          ],
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

  Future<void> _save() async {
    if (_nameCtrl.text.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Name is required')));
      return;
    }
    setState(() => _saving = true);
    try {
      await VaultService.createEntry(
        name: _nameCtrl.text,
        url: _urlCtrl.text,
        username: _usernameCtrl.text,
        password: _passwordCtrl.text,
        notes: _notesCtrl.text,
        folderId: _folderId,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _saving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'save the entry'))),
        );
      }
    }
  }
}
