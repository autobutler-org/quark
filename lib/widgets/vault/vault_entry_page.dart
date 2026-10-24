import 'package:flutter/material.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One vault entry, pushed over the vault page: its details, with edit and
/// delete in the bar, or the form that edits it. With no [entryId] it is the
/// form for a new entry.
///
/// Everything it saves or deletes goes through [controller], which encrypts
/// it; it pops itself once the entry is saved as new or deleted, and when
/// the vault locks under it.
///
/// Keys: `vault_entry_edit` and `vault_entry_delete` on the bar buttons, and
/// `delete_vault_entry_confirm` on the confirmation.
class VaultEntryPage extends StatefulWidget {
  /// Creates the page for entry [entryId], or a new one.
  const VaultEntryPage({required this.controller, this.entryId, super.key});

  /// The vault the entry is in.
  final VaultController controller;

  /// The entry shown, or null for a new one.
  final int? entryId;

  @override
  State<VaultEntryPage> createState() => _VaultEntryPageState();
}

class _VaultEntryPageState extends State<VaultEntryPage> {
  late bool _editing = widget.entryId == null;
  bool _showPassword = false;
  bool _saving = false;
  bool _left = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onVaultChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onVaultChanged);
    super.dispose();
  }

  /// Leaves once the vault locks, or the entry is deleted elsewhere: what was
  /// on screen is no longer the vault's to show.
  void _onVaultChanged() {
    final id = widget.entryId;
    final gone = id != null && widget.controller.itemById(id) == null;
    if (widget.controller.status != VaultStatus.unlocked || gone) _leave();
  }

  /// Pops this page, once however many changes ask for it.
  void _leave() {
    if (_left || !mounted) return;
    _left = true;
    Navigator.of(context).pop();
  }

  Future<void> _save(VaultEntryDraft draft) async {
    setState(() => _saving = true);
    try {
      await widget.controller.saveDraft(draft, id: widget.entryId);
      if (!mounted) return;
      if (widget.entryId == null) {
        _leave();
      } else {
        setState(() => _editing = false);
      }
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.vault(e, 'save the entry'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(int id) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete ${widget.controller.draftOf(id).name}?',
      body:
          "It's removed from your vault on every device. This can't be "
          'undone.',
      keyPrefix: 'delete_vault_entry',
    );
    if (!confirmed || !mounted) return;
    try {
      // The controller's change pops this page.
      await widget.controller.delete(id);
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.vault(e, 'delete the entry'));
    }
  }

  String _generate() {
    try {
      return widget.controller.generate();
    } catch (e) {
      showMessage(context, Errors.message(e, 'generate a password'));
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final id = widget.entryId;
    final draft = id == null ? const VaultEntryDraft() : controller.draftOf(id);
    return Scaffold(
      appBar: ChromeAppBar(
        title: Text(
          id == null
              ? 'New entry'
              : _editing
              ? 'Edit entry'
              : draft.name,
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            spacing: QuarkTokens.of(context).spacingSm,
            children: [
              if (id != null && !_editing) ...[
                QuarkBarIconButton(
                  key: const ValueKey('vault_entry_edit'),
                  icon: QuarkIcons.edit_outlined,
                  tooltip: 'Edit entry',
                  onPressed: () => setState(() => _editing = true),
                ),
                QuarkBarIconButton(
                  key: const ValueKey('vault_entry_delete'),
                  icon: QuarkIcons.delete_outline,
                  tooltip: 'Delete entry',
                  destructive: true,
                  onPressed: () => _delete(id),
                ),
              ],
              const AppThemeToggle(),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: id == null || _editing
            ? VaultEntryForm(
                initial: draft,
                folders: controller.folderOptions,
                isSaving: _saving,
                onGeneratePassword: _generate,
                onSave: _save,
              )
            : SingleChildScrollView(
                child: VaultEntryDetails(
                  entry: draft,
                  folderName: controller.folderNameOf(draft.folderId),
                  showPassword: _showPassword,
                  onToggleShowPassword: () {
                    controller.touch();
                    setState(() => _showPassword = !_showPassword);
                  },
                  onCopy: (label, value) {
                    controller.touch();
                    copyToClipboard(context, value, message: '$label copied');
                  },
                ),
              ),
      ),
    );
  }
}
