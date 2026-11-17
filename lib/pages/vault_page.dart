import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/file_save.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/clipboard_utils.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/utils/vault_export.dart';
import 'package:quark/utils/vault_import.dart';
import 'package:quark/utils/vault_import_summary.dart';
import 'package:quark/utils/web_download_stub.dart'
    if (dart.library.html) 'package:quark/utils/web_download_web.dart'
    as web_download;
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/vault/vault_bar_bottom.dart';
import 'package:quark/widgets/vault/vault_create_sheet.dart';
import 'package:quark/widgets/vault/vault_entry_page.dart';
import 'package:quark/widgets/vault/vault_error_view.dart';
import 'package:quark/widgets/vault/vault_export_menu.dart';
import 'package:quark/widgets/vault/vault_start_over_dialog.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Vault page (#3461): every signed-in account's own password vault,
/// encrypted on the client.
///
/// A composition over [VaultController], which holds the vault's state and
/// does all of its crypto: set up or unlock with the login password, then
/// list, search, add, edit, delete, import and export. A vault restored onto
/// new hardware asks for the password it was backed up with and the password
/// the account signs in with now, and then opens with that sign-in password.
///
/// On a phone (#4234) the bar holds Lock vault and a More menu with Export;
/// the search field and folder chips come first under it, and a `+` button
/// opens New entry, New folder and Import. Wider, `VaultBarBottom` carries
/// those four. Each entry row's ⋮ copies its password or username, edits it,
/// or deletes it.
class VaultPage extends StatefulWidget {
  /// Creates the page over [controller], the app's vault by default.
  const VaultPage({this.controller, super.key});

  /// The vault shown. Tests pass one with fake services.
  final VaultController? controller;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final VaultController _vault =
      widget.controller ?? VaultController.instance;
  bool _importing = false;

  @override
  Future<void> refresh() => _vault.load();

  void _openEntry([int? id, bool edit = false]) {
    _vault.touch();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            VaultEntryPage(controller: _vault, entryId: id, startEditing: edit),
      ),
    );
  }

  /// Runs what entry [id]'s ⋮ menu chose.
  Future<void> _entryAction(int id, VaultEntryAction action) async {
    _vault.touch();
    final entry = _vault.draftOf(id);
    switch (action) {
      case VaultEntryAction.copyPassword:
        await copyToClipboard(
          context,
          entry.password,
          message: 'Password copied',
        );
      case VaultEntryAction.copyUsername:
        await copyToClipboard(
          context,
          entry.username,
          message: 'Username copied',
        );
      case VaultEntryAction.edit:
        _openEntry(id, true);
      case VaultEntryAction.delete:
        final confirmed = await confirmDestructive(
          context,
          title: 'Delete ${entry.name}?',
          body:
              "It's removed from your vault on every device. This can't be "
              'undone.',
          keyPrefix: 'delete_vault_entry',
        );
        if (!confirmed) return;
        try {
          await _vault.delete(id);
        } catch (e) {
          if (mounted) {
            showMessage(context, Errors.vault(e, 'delete the entry'));
          }
        }
    }
  }

  /// A phone's `+`: New entry, New folder and Import in a sheet.
  void _showCreateSheet() => VaultCreateSheet.show(
    context,
    onNewEntry: _openEntry,
    onNewFolder: _newFolder,
    onImport: _importing ? null : _import,
  );

  /// Deletes the vault once the login password re-confirms it (#3615).
  Future<void> _startOver() async {
    final password = await QuarkWidget.showDialog<String>(
      context,
      builder: (dialogContext) => VaultStartOverDialog(
        onConfirm: (typed) => Navigator.of(dialogContext).pop(typed),
        onCancel: () => Navigator.of(dialogContext).pop(),
      ),
    );
    if (password == null || !mounted) return;
    try {
      await _vault.startOver(password);
    } catch (e) {
      if (mounted) showMessage(context, Errors.message(e, 'delete your vault'));
    }
  }

  /// Asks for a folder's name and makes it. The dialog stays open with what
  /// was typed until the folder is saved, and shows why it was not.
  Future<void> _newFolder() async {
    _vault.touch();
    var saving = false;
    Object? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => QuarkNameDialog(
          title: 'New folder',
          label: 'Folder name',
          submitLabel: 'Create',
          maxLength: 100,
          isSubmitting: saving,
          error: error == null
              ? null
              : Errors.vault(error, 'create the folder'),
          onCancel: () => Navigator.of(dialogContext).pop(),
          onSubmit: (name) async {
            setDialogState(() {
              saving = true;
              error = null;
            });
            try {
              await _vault.createFolder(name);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            } catch (e) {
              if (dialogContext.mounted) {
                setDialogState(() {
                  saving = false;
                  error = e;
                });
              }
            }
          },
        ),
      ),
    );
  }

  /// Deletes folder [id] once the user confirms. Its entries stay, in no folder.
  Future<void> _deleteFolder(int id) async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Delete ${_vault.folderNameOf(id)}?',
      body:
          'The folder is removed on every device. The logins in it are '
          'kept, in no folder.',
      keyPrefix: 'delete_vault_folder',
    );
    if (!confirmed) return;
    try {
      await _vault.delete(id);
    } catch (e) {
      if (mounted) showMessage(context, Errors.vault(e, 'delete the folder'));
    }
  }

  Future<void> _import() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );
    if (file == null || !mounted) return;
    setState(() => _importing = true);
    try {
      final text = await readVaultImport(file.readAsByteStream());
      final summary = vaultImportSummary(await _vault.import(text));
      if (mounted) showMessage(context, summary);
    } catch (e) {
      if (mounted) {
        showMessage(context, Errors.message(e, 'import your entries'));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// Saves the export through the browser's download on the web and the
  /// platform's save dialog elsewhere. The decrypted vault is already in
  /// memory, so the file is written from it whole.
  Future<void> _export(VaultExportFormat format) async {
    try {
      final bytes = utf8.encode(_vault.export(format));
      final saved = kIsWeb
          ? await web_download.saveBytesForDownload(bytes, format.fileName)
          : await saveBytesThroughDialog(bytes, format.fileName);
      if (saved != null && mounted) {
        showMessage(context, 'Exported as ${format.fileName}');
      }
    } catch (e) {
      if (mounted) showMessage(context, Errors.message(e, 'export your vault'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _vault,
      builder: (context, _) {
        final status = _vault.status;
        final unlocked = status == VaultStatus.unlocked;
        final restored = _vault.opensWithBackupPassword;
        final formError = _vault.formError;
        final error = _vault.error;
        // A phone's bar holds two actions, so the create actions move to a
        // + button and Export to More (#4234).
        final phone = QuarkAppBar.isCompact(context);
        return QuarkPageScaffold(
          title: 'Vault',
          icon: QuarkIcons.lock_outline,
          appBar: QuarkAppBar(
            label: 'Vault',
            icon: QuarkIcons.lock_outline,
            // A locked vault has nothing on screen to reload.
            onRefresh: unlocked ? manualRefresh : null,
            isRefreshing: isRefreshing,
            actions: [
              if (unlocked)
                QuarkBarIconButton(
                  key: const ValueKey('vault_lock'),
                  icon: QuarkIcons.lock_open,
                  tooltip: 'Lock vault',
                  onPressed: _vault.lock,
                ),
              if (unlocked && phone)
                VaultExportMenu(onExport: _export, asMore: true),
            ],
            bottom: unlocked && !phone
                ? VaultBarBottom(
                    onNewEntry: _openEntry,
                    onNewFolder: _newFolder,
                    onImport: _importing ? null : _import,
                    onExport: _export,
                  )
                : null,
          ),
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.vault),
          floatingActionButton: unlocked && phone
              ? QuarkCreateFab(
                  key: const ValueKey('vault_create_fab'),
                  tooltip: 'Add',
                  visible: true,
                  onPressed: _showCreateSheet,
                )
              : null,
          body: switch (status) {
            VaultStatus.loading => const Center(child: QuarkLoader()),
            VaultStatus.error when isQuarkUnreachableError(error!) =>
              QuarkDisconnectedView(
                hostAddress: AppSettings.instance.activeHost,
                onRetry: manualRefresh,
                onManageHosts: () =>
                    context.go(AppRoutes.settingsTab(SettingsTab.general)),
              ),
            VaultStatus.error => VaultErrorView(
              message: Errors.message(error, 'load your vault'),
              onRetry: manualRefresh,
            ),
            VaultStatus.noVault => VaultPasswordForm(
              key: const ValueKey('vault_setup'),
              icon: QuarkIcons.shield_outlined,
              title: 'Set up your vault',
              message:
                  'Your vault is encrypted on your devices with the password '
                  'you sign in to Quark with, so there is no second password '
                  'to remember. Nobody else, not even an admin, can open it.',
              submitLabel: 'Set up vault',
              phraseHelp:
                  'Your account recovery phrase lets a recovery keep this '
                  'vault if you forget your password. A mistyped phrase is '
                  "not checked: it simply won't open the vault.",
              isBusy: _vault.isBusy,
              error: formError == null
                  ? null
                  : Errors.message(formError, 'set up your vault'),
              onSubmit: (password, phrase, [_ = '']) =>
                  _vault.setUp(password, phrase: phrase),
            ),
            VaultStatus.locked => VaultPasswordForm(
              key: const ValueKey('vault_unlock'),
              title: 'Your vault is locked',
              message: restored
                  ? 'Enter the password you had when this vault was backed '
                        'up. Your vault is then re-wrapped under the password '
                        'you sign in with now, and that password opens it '
                        'from then on.'
                  : 'Enter the password you sign in to Quark with. Your vault '
                        'opens on this device; the Quark never sees what is in it.',
              submitLabel: 'Unlock',
              secondPasswordLabel: restored
                  ? 'Password you sign in with'
                  : null,
              isBusy: _vault.isBusy,
              error: formError == null
                  ? null
                  : Errors.message(formError, 'unlock your vault'),
              secondaryLabel: 'Start over',
              onSecondary: _startOver,
              onSubmit: (password, _, [login = '']) =>
                  _vault.unlock(password, loginPassword: login),
            ),
            // A phone's bar has no refresh slot, so the list pulls to
            // refresh (#4150).
            VaultStatus.unlocked => RefreshIndicator(
              onRefresh: manualRefresh,
              child: VaultEntryList(
                entries: _vault.visibleRows,
                folders: _vault.folderOptions,
                selectedFolderId: _vault.folderId,
                initialQuery: _vault.query,
                vaultIsEmpty: _vault.entries.isEmpty,
                onSearchChanged: _vault.search,
                onFolderSelected: _vault.filterFolder,
                onDeleteFolder: _deleteFolder,
                onTapEntry: _openEntry,
                onEntryAction: _entryAction,
              ),
            ),
          },
        );
      },
    );
  }
}
