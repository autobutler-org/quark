import 'dart:async';
import 'dart:convert';

import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark/utils/rename_doc_sheet.dart';
import 'package:quark/utils/sheet_tab_names.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/spreadsheet_editor/sheet_tab_view.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/services/app_settings.dart';

// ---------------------------------------------------------------------------
// Per-tab state
// ---------------------------------------------------------------------------

class _SheetTab {
  String name;
  final DataTable table;
  final DataSheetController controller;

  _SheetTab({
    required this.name,
    required this.table,
    required this.controller,
  });

  void dispose() => controller.dispose();

  Map<String, dynamic> toJson() => {
    'name': name,
    'data': table.toJson(),
    'columnWidths': controller.columnWidths,
    'rowHeights': controller.rowHeights,
  };
}

// ---------------------------------------------------------------------------
// Page
// ---------------------------------------------------------------------------

/// The editor for one spreadsheet: a tab per sheet, which can be added, renamed or deleted, all saved back to the
/// Quark. Once the sheet has loaded, the title renames the file itself.
class SpreadsheetEditorPage extends StatefulWidget {
  final String filePath;
  final String deviceSerial;

  const SpreadsheetEditorPage({
    required this.filePath,
    this.deviceSerial = '',
    super.key,
  });

  @override
  State<SpreadsheetEditorPage> createState() => _SpreadsheetEditorPageState();
}

class _SpreadsheetEditorPageState extends State<SpreadsheetEditorPage> {
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  bool _renaming = false;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;

  List<_SheetTab> _tabs = [];
  int _selected = 0;

  static const _autoSaveDelay = Duration(seconds: 2);
  Timer? _autoSaveTimer;

  String get _displayName =>
      fileNameWithoutExtension(widget.filePath, '.qsheet');

  /// The editor's own way out when nothing was pushed underneath it.
  ///
  /// [AppBar] implies a back button only when the navigator can pop. The
  /// sheets list, a search hit and the file browser all open a sheet at its own
  /// URL (#2078), so nothing is underneath it and this is the button every
  /// entry point gets. It lands in the folder that holds the sheet, not the
  /// home folder (#1749).
  Widget? _backButton() => Navigator.of(context).canPop()
      ? null
      : BackButton(onPressed: _leaveForContainingFolder);

  void _leaveForContainingFolder() =>
      context.go(AppRoutes.containingFolder(widget.filePath));

  @override
  void initState() {
    super.initState();
    _loadFile();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    for (final tab in _tabs) {
      tab.dispose();
    }
    super.dispose();
  }

  // ── Load ──────────────────────────────────────────────────────────────────

  Future<void> _loadFile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final bytes = await FilesService.downloadFileBytes(
        widget.filePath,
        serial: serialOrNull(widget.deviceSerial),
      );
      if (!mounted) return;

      final tabs = _parseTabs(bytes);

      for (final tab in tabs) {
        tab.controller.addListener(_onSheetChanged);
      }

      setState(() {
        _tabs = tabs;
        _selected = 0;
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  List<_SheetTab> _parseTabs(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return [_makeEmptyTab('Sheet 1')];

    final jsonData =
        jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>? ?? {};
    final tabsJson = jsonData['tabs'] as List<dynamic>? ?? [];
    if (tabsJson.isEmpty) return [_makeEmptyTab('Sheet 1')];

    return tabsJson
        .map((t) => _tabFromJson(t as Map<String, dynamic>))
        .toList();
  }

  _SheetTab _tabFromJson(Map<String, dynamic> tabMap) {
    final name = (tabMap['name'] as String?) ?? 'Sheet';
    final dataMap = tabMap['data'] as Map<String, dynamic>? ?? {};
    final table = DataTable.fromJson(dataMap);
    if (table.rows.isEmpty) {
      table.rows.add(DataRow([DataCell('')]));
    }
    final columnWidths = (tabMap['columnWidths'] as List<dynamic>?)
        ?.map((v) => (v as num).toDouble())
        .toList();
    final rowHeights = (tabMap['rowHeights'] as List<dynamic>?)
        ?.map((v) => (v as num).toDouble())
        .toList();
    final controller = DataSheetController.fromTable(
      table,
      columnWidths: columnWidths,
      rowHeights: rowHeights,
    );
    return _SheetTab(name: name, table: table, controller: controller);
  }

  _SheetTab _makeEmptyTab(String name) {
    final table = DataTable([
      DataRow([DataCell('')]),
    ]);
    final controller = DataSheetController.fromTable(table);
    return _SheetTab(name: name, table: table, controller: controller);
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────

  List<String> get _tabNames => [for (final tab in _tabs) tab.name];

  /// Puts [tab] at [index], selects it, and saves through the autosave.
  void _insertTab(int index, _SheetTab tab) {
    tab.controller.addListener(_onSheetChanged);
    setState(() {
      _tabs.insert(index, tab);
      _selected = index;
    });
    _onSheetChanged();
  }

  void _addTab() =>
      _insertTab(_tabs.length, _makeEmptyTab(nextSheetName(_tabNames)));

  /// A deep copy, made by round-tripping the tab through its saved form.
  void _duplicateTab(int index) {
    final json =
        jsonDecode(jsonEncode(_tabs[index].toJson())) as Map<String, dynamic>;
    json['name'] = copySheetName(_tabs[index].name, _tabNames);
    _insertTab(index + 1, _tabFromJson(json));
  }

  void _moveTab(int from, int to) {
    setState(() {
      _tabs.insert(to, _tabs.removeAt(from));
      _selected = to;
    });
    _onSheetChanged();
  }

  /// Opens the rename dialog. A refused name shows in the open dialog.
  Future<void> _renameTab(int index) async {
    final tab = _tabs[index];
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => QuarkNameDialog(
          title: 'Rename ${tab.name}',
          label: 'Sheet name',
          submitLabel: 'Rename',
          initialName: tab.name,
          error: error,
          onCancel: () => Navigator.of(dialogContext).pop(),
          onSubmit: (name) {
            final refusal = sheetNameError(name, _tabNames, index);
            if (refusal != null) {
              setDialogState(() => error = refusal);
              return;
            }
            Navigator.of(dialogContext).pop();
            if (name == tab.name) return;
            setState(() => tab.name = name);
            _onSheetChanged();
          },
        ),
      ),
    );
  }

  Future<void> _deleteTab(int index) async {
    final tab = _tabs[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => ConfirmDeleteDialog(
        title: 'Delete ${tab.name}?',
        body: 'Everything on this sheet is deleted with it.',
        keyPrefix: 'delete_sheet',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _tabs.removeAt(index);
      if (_selected > index || _selected == _tabs.length) _selected--;
    });
    // The grid showing it lets go of the controller on the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => tab.dispose());
    _onSheetChanged();
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  void _onSheetChanged() {
    if (!_dirty && mounted) setState(() => _dirty = true);
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(_autoSaveDelay, _doSave);
  }

  Future<void> _doSave() async {
    if (_saving || !mounted) return;
    setState(() => _saving = true);
    try {
      final jsonStr = jsonEncode({
        'tabs': _tabs.map((t) => t.toJson()).toList(),
      });
      final bytes = utf8.encode(jsonStr);
      final fileName = '$_displayName.qsheet';
      final parentDir = parentPath(widget.filePath);
      final file = http.MultipartFile.fromBytes(
        'files',
        bytes,
        filename: fileName,
      );
      await FilesService.uploadFilesFromFormData(
        parentDir,
        [file],
        serial: serialOrNull(widget.deviceSerial),
        overwrite: true,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'save the sheet'))),
      );
    }
  }

  Future<void> _manualSave() async {
    _autoSaveTimer?.cancel();
    try {
      await _doSave();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'save the sheet'))),
      );
    }
  }

  /// Renames the spreadsheet file from the title.
  ///
  /// A dirty sheet is saved first. [_doSave] reports a failure itself and
  /// leaves the sheet dirty, so a failed save stops here instead of renaming.
  /// Cancelling the dialog leaves the sheet where it is.
  Future<void> _renameSpreadsheet() async {
    if (_renaming) return;
    _renaming = true;
    try {
      if (_dirty) {
        _autoSaveTimer?.cancel();
        await _doSave();
        if (!mounted || _dirty) return;
      }

      final List<FileNode> siblings;
      try {
        final serial = serialOrNull(widget.deviceSerial);
        siblings = await FilesService.getFiles(
          parentPath(widget.filePath),
          serials: serial == null ? null : [serial],
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'rename the sheet'))),
        );
        return;
      }
      if (!mounted) return;

      final apiPath = widget.filePath.trim().replaceAll(RegExp(r'^/+|/+$'), '');
      final renamed = await renameDocOrSheet(
        context,
        FileNode(
          name: apiPath.split('/').last,
          size: 0,
          isDir: false,
          deviceName: '',
          devicePath: '',
          deviceSerial: widget.deviceSerial,
          dirPath: apiPath,
        ),
        siblings: siblings,
      );
      if (renamed == null || !mounted) return;
      _autoSaveTimer?.cancel();
      context.go(
        AppRoutes.sheetFile(
          renamed,
          serial: widget.deviceSerial.isEmpty ? null : widget.deviceSerial,
        ),
      );
    } finally {
      _renaming = false;
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.filePath.split('/').last;
    final error = _error;
    final Widget page;

    if (_loading) {
      page = Scaffold(
        appBar: AppBar(
          leading: _backButton(),
          title: Text(title),
          actions: const [AppThemeToggle()],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    } else if (error != null) {
      page = Scaffold(
        appBar: AppBar(
          leading: _backButton(),
          title: Text(title),
          actions: const [AppThemeToggle()],
        ),
        body: isQuarkUnreachableError(error)
            ? QuarkDisconnectedView(
                hostAddress: AppSettings.instance.activeHost,
                onRetry: _loadFile,
              )
            : Center(child: Text(Errors.message(error, 'load the sheet'))),
      );
    } else {
      final tab = _tabs[_selected];
      page = Scaffold(
        appBar: AppBar(
          leading: _backButton(),
          title: Tooltip(
            message: 'Rename',
            child: InkWell(
              key: const ValueKey('sheet_rename_title'),
              onTap: _renameSpreadsheet,
              child: Text(title),
            ),
          ),
          actions: [
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                icon: Icon(_dirty ? QuarkIcons.save : QuarkIcons.save_outlined),
                tooltip: 'Save',
                onPressed: _manualSave,
              ),
            const AppThemeToggle(),
          ],
        ),
        body: SheetTabView(
          key: ObjectKey(tab),
          controller: tab.controller,
          table: tab.table,
        ),
        bottomNavigationBar: SafeArea(
          top: false,
          child: SheetTabStrip(
            tabNames: _tabNames,
            selectedIndex: _selected,
            onSelect: (index) => setState(() => _selected = index),
            onAdd: _addTab,
            onRename: _renameTab,
            onDuplicate: _duplicateTab,
            onMoveLeft: (index) => _moveTab(index, index - 1),
            onMoveRight: (index) => _moveTab(index, index + 1),
            onDelete: _deleteTab,
          ),
        ),
      );
    }

    final canPop = Navigator.of(context).canPop();
    return PopScope(
      // With nothing underneath, a system back would close the app; it
      // leaves for the containing folder, as the app bar's back button does.
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) _leaveForContainingFolder();
      },
      child: page,
    );
  }
}
