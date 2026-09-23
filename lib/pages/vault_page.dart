import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/router.dart';
import 'package:quark/services/vault_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/utils/web_download_stub.dart'
    if (dart.library.html) 'package:quark/utils/web_download_web.dart'
    as web_download;
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/vault/entry_detail_page.dart';
import 'package:quark/widgets/vault/entry_editor_page.dart';
import 'package:quark/widgets/vault/vault_device_disconnected_view.dart';
import 'package:quark/widgets/vault/vault_entry_list.dart';
import 'package:quark/widgets/vault/vault_error_view.dart';
import 'package:quark/widgets/vault/vault_setup_view.dart';
import 'package:quark/widgets/vault/vault_unlock_view.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/services/app_settings.dart';

/// The Vault page: set up, unlock, and browse the Quark's encrypted password vault.
class VaultPage extends StatefulWidget {
  const VaultPage({super.key});

  @override
  State<VaultPage> createState() => _VaultPageState();
}

class _VaultPageState extends State<VaultPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  VaultStatus? _status;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637). Distinct
  /// from [VaultDeviceDisconnectedView], which is the vault's own USB drive
  /// being unplugged from a Quark the app can reach perfectly well.
  Object? _error;

  List<VaultEntryItem> _entries = [];
  List<VaultFolder> _folders = [];
  int? _selectedFolderId;
  String _searchQuery = '';

  final _setupPasswordCtrl = TextEditingController();
  final _setupConfirmCtrl = TextEditingController();
  String? _setupError;

  final _unlockPasswordCtrl = TextEditingController();
  String? _unlockError;
  bool _unlocking = false;

  @override
  void dispose() {
    _setupPasswordCtrl.dispose();
    _setupConfirmCtrl.dispose();
    _unlockPasswordCtrl.dispose();
    super.dispose();
  }

  /// The whole vault state, in the order the page needs it: the status picks
  /// the view, and an unlocked vault's entries follow. The app bar's refresh
  /// comes through here rather than straight to [_loadEntries], so a vault
  /// that locked itself since the last look is noticed instead of listed.
  @override
  Future<void> refresh() => _loadStatus();

  Future<void> _loadStatus() async {
    try {
      final status = await VaultService.getStatus();
      if (!mounted) return;
      final loadsEntries = status.initialized && !status.locked;
      setState(() {
        _status = status;
        // Cleared on success rather than up front, so a poll against an
        // unreachable Quark does not blink the error view away and back.
        if (!loadsEntries) _error = null;
      });
      if (loadsEntries) await _loadEntries();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _loadEntries() async {
    try {
      final results = await Future.wait([
        VaultService.listEntries(),
        VaultService.listFolders(),
      ]);
      if (!mounted) return;
      setState(() {
        _entries = results[0] as List<VaultEntryItem>;
        _folders = results[1] as List<VaultFolder>;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  List<VaultEntryItem> get _filteredEntries {
    var items = _entries;
    if (_selectedFolderId != null) {
      items = items.where((e) => e.folderId == _selectedFolderId).toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      items = items
          .where(
            (e) =>
                e.name.toLowerCase().contains(q) ||
                e.urlHost.toLowerCase().contains(q),
          )
          .toList();
    }
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final unlocked = _status?.initialized == true && !(_status?.locked ?? true);
    final showFab = unlocked && MediaQuery.of(context).size.width < 860;
    return Scaffold(
      appBar: QuarkAppBar(
        label: 'Vault',
        icon: QuarkIcons.lock_outline,
        // A locked or uninitialized vault has nothing on screen to reload.
        onRefresh: unlocked ? manualRefresh : null,
        isRefreshing: isRefreshing,
        actions: [
          if (unlocked) ...[
            // Below the floating button's breakpoint the button is the way
            // in, and a second one in a full bar would crowd out the rest.
            if (!showFab)
              QuarkBarChip(
                key: const ValueKey('vault_new_entry'),
                icon: QuarkIcons.add_rounded,
                label: 'New entry',
                onPressed: () => _showEntryEditor(context),
              ),
            QuarkBarIconButton(
              key: const ValueKey('vault_lock'),
              icon: QuarkIcons.lock_open,
              tooltip: 'Lock vault',
              onPressed: _lockVault,
            ),
            MenuAnchor(
              menuChildren: [
                MenuItemButton(
                  key: const ValueKey('vault_import'),
                  leadingIcon: const Icon(QuarkIcons.upload_rounded),
                  onPressed: () => _showImportDialog(context),
                  child: const Text('Import'),
                ),
                MenuItemButton(
                  key: const ValueKey('vault_export_json'),
                  leadingIcon: const Icon(QuarkIcons.download_outlined),
                  onPressed: () => _doExport('json'),
                  child: const Text('Export as JSON'),
                ),
                MenuItemButton(
                  key: const ValueKey('vault_export_csv'),
                  leadingIcon: const Icon(QuarkIcons.download_outlined),
                  onPressed: () => _doExport('csv'),
                  child: const Text('Export as CSV'),
                ),
              ],
              builder: (context, controller, _) => QuarkBarIconButton(
                key: const ValueKey('vault_more'),
                icon: QuarkIcons.more_vert,
                tooltip: 'Import and export',
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
            ),
          ],
          const AppThemeToggle(),
        ],
      ),
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.vault),
      body: _buildBody(),
      floatingActionButton: showFab
          ? FloatingActionButton(
              onPressed: () => _showEntryEditor(context),
              child: const Icon(QuarkIcons.add),
            )
          : null,
    );
  }

  /// Picks the view for the current status. Every branch is one widget, so
  /// there is no subtree hiding in here.
  Widget _buildBody() {
    if (isInitialLoad) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      if (isQuarkUnreachableError(error)) {
        return QuarkDisconnectedView(
          hostAddress: AppSettings.instance.activeHost,
          onRetry: _loadStatus,
          onManageHosts: () => context.go(AppRoutes.settings),
        );
      }
      return VaultErrorView(
        message: Errors.message(error, 'load your vault'),
        onRetry: _loadStatus,
      );
    }
    final status = _status;
    if (status == null) return const SizedBox.shrink();

    if (!status.initialized) {
      return VaultSetupView(
        passwordController: _setupPasswordCtrl,
        confirmController: _setupConfirmCtrl,
        error: _setupError,
        onCreate: _doSetup,
      );
    }
    if (!status.deviceConnected) {
      return VaultDeviceDisconnectedView(onRetry: _loadStatus);
    }
    if (status.locked) {
      return VaultUnlockView(
        passwordController: _unlockPasswordCtrl,
        lockReason: status.lockReason,
        error: _unlockError,
        unlocking: _unlocking,
        onUnlock: _doUnlock,
      );
    }
    return VaultEntryList(
      entries: _filteredEntries,
      vaultIsEmpty: _entries.isEmpty,
      folders: _folders,
      onSearchChanged: (v) => setState(() => _searchQuery = v),
      onFolderSelected: (v) => setState(() => _selectedFolderId = v),
      onTapEntry: (id) => _showEntryDetail(context, id),
    );
  }

  Future<void> _doSetup() async {
    if (_setupPasswordCtrl.text.length < 8) {
      setState(() => _setupError = 'Password must be at least 8 characters');
      return;
    }
    if (_setupPasswordCtrl.text != _setupConfirmCtrl.text) {
      setState(() => _setupError = 'Passwords do not match');
      return;
    }
    try {
      await VaultService.setup(_setupPasswordCtrl.text);
      _setupPasswordCtrl.clear();
      _setupConfirmCtrl.clear();
      _loadStatus();
    } catch (e) {
      setState(() => _setupError = Errors.message(e, 'create your vault'));
    }
  }

  Future<void> _doUnlock() async {
    setState(() {
      _unlockError = null;
      _unlocking = true;
    });
    try {
      final ok = await VaultService.unlock(_unlockPasswordCtrl.text);
      if (!ok) {
        setState(() {
          _unlockError = 'Incorrect password';
          _unlocking = false;
        });
        return;
      }
      _unlockPasswordCtrl.clear();
      _loadStatus();
    } catch (e) {
      setState(() {
        _unlockError = Errors.message(e, 'unlock your vault');
        _unlocking = false;
      });
    }
  }

  Future<void> _lockVault() async {
    try {
      await VaultService.lock();
      _loadStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'lock your vault'))),
        );
      }
    }
  }

  Future<void> _showImportDialog(BuildContext context) async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['csv', 'json'],
    );
    if (file == null) return;

    if (!mounted) return;
    final format = await QuarkWidget.showDialog<String>(
      context, // ignore: use_build_context_synchronously
      builder: (ctx) => QuarkWidget.alertDialog(
        title: const Text('Import format'),
        content: Text('Importing "${file.name}". Choose the format:'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'auto'),
            child: const Text('Auto-detect'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'bitwarden'),
            child: const Text('Bitwarden CSV'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return;

    try {
      final resp = await VaultService.importEntries(
        fileBytes: await file.readAsBytes(),
        fileName: file.name,
        format: format,
      );
      _loadEntries();
      if (!mounted) return;
      final imported = resp['imported'] ?? 0;
      final skipped = resp['skipped'] ?? 0;
      final errors = (resp['errors'] as List?)?.length ?? 0;
      ScaffoldMessenger.of(
        context, // ignore: use_build_context_synchronously
      ).showSnackBar(
        SnackBar(
          content: Text(
            'Imported $imported entries'
            '${skipped > 0 ? ', $skipped skipped (duplicates)' : ''}'
            '${errors > 0 ? ', $errors errors' : ''}',
          ),
        ),
      );
    } on VaultLockedException {
      _loadStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context, // ignore: use_build_context_synchronously
        ).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'import your entries'))),
        );
      }
    }
  }

  Future<void> _doExport(String format) async {
    try {
      final bytes = await VaultService.exportEntries(format: format);
      final fileName = format == 'csv' ? 'quark_vault.csv' : 'quark_vault.json';
      await web_download.saveBytesForDownload(
        Uint8List.fromList(bytes),
        fileName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Exported as $fileName')));
    } on VaultLockedException {
      _loadStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'export your vault'))),
        );
      }
    }
  }

  Future<void> _showEntryDetail(BuildContext context, int entryId) async {
    try {
      final detail = await VaultService.getEntry(entryId);
      if (!mounted) return;
      final deleted = await Navigator.push<bool>(
        context, // ignore: use_build_context_synchronously
        MaterialPageRoute(
          builder: (_) => EntryDetailPage(
            entry: detail,
            folders: _folders,
            onSave: (updated) async {
              await VaultService.updateEntry(
                id: detail.id,
                name: updated['name'] as String,
                url: updated['url'] as String? ?? '',
                username: updated['username'] as String? ?? '',
                password: updated['password'] as String? ?? '',
                notes: updated['notes'] as String? ?? '',
                totpSecret: updated['totpSecret'] as String? ?? '',
                folderId: updated['folderId'] as int?,
              );
              _loadEntries();
            },
            onDelete: () async {
              await VaultService.deleteEntry(detail.id);
              _loadEntries();
            },
          ),
        ),
      );
      if (deleted == true) _loadEntries();
    } on VaultLockedException {
      _loadStatus();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context, // ignore: use_build_context_synchronously
        ).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'delete the entry'))),
        );
      }
    }
  }

  Future<void> _showEntryEditor(BuildContext context) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => EntryEditorPage(folders: _folders)),
    );
    if (result == true) _loadEntries();
  }
}
