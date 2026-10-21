import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/quicktype_controller.dart';
import 'package:quark/controllers/recovery_phrase_controller.dart';
import 'package:quark/controllers/vault_biometric_controller.dart';
import 'package:quark/controllers/vault_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/file_save.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
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
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/recovery_phrase/add_recovery_phrase_offer.dart';
import 'package:quark/widgets/vault/vault_entry_page.dart';
import 'package:quark/widgets/vault/vault_error_view.dart';
import 'package:quark/widgets/vault/vault_export_menu.dart';
import 'package:quark/widgets/vault/vault_start_over_dialog.dart';
import 'package:quark/widgets/vault_quicktype/vault_quicktype_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Vault page (#3461): every signed-in account's own password vault,
/// encrypted on the client.
///
/// A composition over [VaultController], which holds the vault's state and
/// does all of its crypto: set up or unlock with the login password, then
/// list, search, add, edit, delete, import and export. Where
/// [VaultBiometricController] says the device can, the lock screen opens
/// with Face ID, Touch ID or a fingerprint instead (#3595), and the open
/// vault offers to turn that on and has the setting in its bar. On iOS with
/// biometric unlock on, the bar also has the opt-in for QuickType suggestions
/// (#3599). An open vault whose key has no wrap under the recovery phrase
/// offers to add one, so a recovery keeps it (#3530).
class VaultPage extends StatefulWidget {
  /// Creates the page over [controller], the app's vault by default,
  /// [biometric], the app's biometric unlock by default, [recoveryPhrase],
  /// the app's recovery phrase offer by default, and [quickType], the app's
  /// QuickType setting by default.
  const VaultPage({
    this.controller,
    this.biometric,
    this.recoveryPhrase,
    this.quickType,
    super.key,
  });

  /// The vault shown. Tests pass one with fake services.
  final VaultController? controller;

  /// The biometric unlock. Tests pass one with a fake keystore.
  final VaultBiometricController? biometric;

  /// The recovery phrase offer. Tests pass one with fake services.
  final RecoveryPhraseController? recoveryPhrase;

  /// The QuickType setting. Tests pass one with a fake store.
  final QuickTypeController? quickType;

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final VaultController _vault =
      widget.controller ?? VaultController.instance;
  late final VaultBiometricController _biometric =
      widget.biometric ?? VaultBiometricController.instance;
  late final RecoveryPhraseController _phrase =
      widget.recoveryPhrase ?? RecoveryPhraseController.instance;
  bool _importing = false;

  /// Whether the user chose to type the password over the biometric.
  bool _usePassword = false;

  @override
  Future<void> refresh() =>
      Future.wait([_vault.load(), _biometric.refresh(), _phrase.check()]);

  /// Sets the vault up, then asks again whether its key has a phrase wrap:
  /// one set up without the phrase is offered it at once.
  Future<void> _setUp(String password, String phrase) async {
    await _vault.setUp(password, phrase: phrase);
    await _phrase.check();
  }

  void _openEntry([int? id]) {
    _vault.touch();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VaultEntryPage(controller: _vault, entryId: id),
      ),
    );
  }

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

  /// The biometric setting, which says what turning it on means before the
  /// switch does anything.
  Future<void> _biometricSettings() async {
    _vault.touch();
    await QuarkWidget.showDialog<void>(
      context,
      builder: (dialogContext) => ListenableBuilder(
        listenable: _biometric,
        builder: (_, _) => VaultBiometricSettingsDialog(
          title: _biometric.settingTitle,
          explanation: _biometric.settingExplanation,
          value: _biometric.enabled,
          isBusy: _biometric.isBusy,
          error: Errors.vaultBiometric(_biometric.error, 'change this setting'),
          onChanged: (on) => on ? _biometric.enable() : _biometric.disable(),
          onClose: () => Navigator.of(dialogContext).pop(),
        ),
      ),
    );
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
      listenable: Listenable.merge([_vault, _biometric, _phrase]),
      builder: (context, _) {
        final status = _vault.status;
        final unlocked = status == VaultStatus.unlocked;
        final formError = _vault.formError;
        final error = _vault.error;
        final biometricError = Errors.vaultBiometric(
          _biometric.error,
          'unlock your vault',
        );
        return QuarkPageScaffold(
          title: 'Vault',
          icon: QuarkIcons.lock_outline,
          // A locked vault has nothing on screen to reload.
          onRefresh: unlocked ? manualRefresh : null,
          isRefreshing: isRefreshing,
          actions: [
            if (unlocked) ...[
              QuarkBarChip(
                key: const ValueKey('vault_new_entry'),
                icon: QuarkIcons.add_rounded,
                label: 'New entry',
                onPressed: _openEntry,
              ),
              QuarkBarChip(
                key: const ValueKey('vault_new_folder'),
                icon: QuarkIcons.create_new_folder_outlined,
                label: 'New folder',
                tooltip: 'New folder',
                onPressed: _newFolder,
              ),
              QuarkBarChip(
                key: const ValueKey('vault_import'),
                icon: QuarkIcons.upload_rounded,
                label: 'Import',
                onPressed: _importing ? null : _import,
              ),
              VaultExportMenu(onExport: _export),
              if (_biometric.isAvailable)
                QuarkBarIconButton(
                  key: const ValueKey('vault_biometric_settings'),
                  icon: QuarkIcons.fingerprint,
                  tooltip: _biometric.settingTitle,
                  onPressed: _biometricSettings,
                ),
              VaultQuickTypeButton(
                controller: widget.quickType,
                onOpen: _vault.touch,
              ),
              QuarkBarIconButton(
                key: const ValueKey('vault_lock'),
                icon: QuarkIcons.lock_open,
                tooltip: 'Lock vault',
                onPressed: _vault.lock,
              ),
            ],
            const AppThemeToggle(),
          ],
          drawer: const AppDrawer(activeSection: QuarkDrawerSection.vault),
          body: Column(
            children: [
              if (_biometric.shouldOffer)
                VaultBiometricOffer(
                  title: '${_biometric.settingTitle}?',
                  message:
                      'Open your vault on this device without typing your '
                      'password.',
                  onEnable: _biometricSettings,
                  onDismiss: _biometric.dismissOffer,
                ),
              if (unlocked && _phrase.offerVault)
                AddRecoveryPhraseOffer(controller: _phrase),
              Expanded(
                child: switch (status) {
                  VaultStatus.loading => const Center(child: QuarkLoader()),
                  VaultStatus.error when isQuarkUnreachableError(error!) =>
                    QuarkDisconnectedView(
                      hostAddress: AppSettings.instance.activeHost,
                      onRetry: manualRefresh,
                      onManageHosts: () => context.go(
                        AppRoutes.settingsTab(SettingsTab.general),
                      ),
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
                    onSubmit: _setUp,
                  ),
                  VaultStatus.locked
                      when _biometric.canUnlock && !_usePassword =>
                    VaultBiometricUnlock(
                      key: const ValueKey('vault_biometric_lock'),
                      title: 'Your vault is locked',
                      message:
                          'Open it with ${_biometric.methodName}, or with the '
                          'password you sign in to Quark with.',
                      unlockLabel: _biometric.settingTitle,
                      isBusy: _biometric.isBusy,
                      error: biometricError,
                      onUnlock: _biometric.unlock,
                      onUsePassword: () => setState(() => _usePassword = true),
                    ),
                  VaultStatus.locked => VaultPasswordForm(
                    key: const ValueKey('vault_unlock'),
                    title: 'Your vault is locked',
                    message:
                        'Enter the password you sign in to Quark with. Your vault '
                        'opens on this device; the Quark never sees what is in it.',
                    submitLabel: 'Unlock',
                    isBusy: _vault.isBusy,
                    // A biometric unlock that fell back here says why.
                    error: formError == null
                        ? biometricError
                        : Errors.message(formError, 'unlock your vault'),
                    secondaryLabel: 'Start over',
                    onSecondary: _startOver,
                    onSubmit: (password, _) => _vault.unlock(password),
                  ),
                  VaultStatus.unlocked => VaultEntryList(
                    entries: _vault.visibleRows,
                    folders: _vault.folderOptions,
                    selectedFolderId: _vault.folderId,
                    initialQuery: _vault.query,
                    vaultIsEmpty: _vault.entries.isEmpty,
                    onSearchChanged: _vault.search,
                    onFolderSelected: _vault.filterFolder,
                    onDeleteFolder: _deleteFolder,
                    onTapEntry: _openEntry,
                  ),
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
