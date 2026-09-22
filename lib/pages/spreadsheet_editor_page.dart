import 'dart:async';
import 'dart:convert';

import 'package:data_table/data_sheet.dart';
import 'package:data_table/data_table.dart';
import 'package:flutter/material.dart' hide DataTable, DataRow, DataCell;
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/files_route_path_utils.dart';
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
/// Quark.
class SpreadsheetEditorPage extends StatefulWidget {
  final String filePath;
  final String deviceSerial;
  final String? overlayTargetRoute;
  final String? overlayCloseRoute;

  const SpreadsheetEditorPage({
    required this.filePath,
    this.deviceSerial = '',
    this.overlayTargetRoute,
    this.overlayCloseRoute,
    super.key,
  });

  @override
  State<SpreadsheetEditorPage> createState() => _SpreadsheetEditorPageState();
}

class _SpreadsheetEditorPageState extends State<SpreadsheetEditorPage> {
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;
  bool _routeMovedExternally = false;

  List<_SheetTab> _tabs = [];
  int _selected = 0;

  static const _autoSaveDelay = Duration(seconds: 2);
  Timer? _autoSaveTimer;

  String get _displayName =>
      fileNameWithoutExtension(widget.filePath, '.qsheet');

  /// The live location, canonicalized. go_router always reports it
  /// percent-encoded while `overlayTargetRoute` is built from the raw path, so
  /// comparing the two directly reported "moved externally" for every file
  /// whose name needed encoding — a space being the common case — and popped
  /// the editor the instant it opened (#1604).
  String _currentRoute() => AppRoutes.canonicalRoute(
    router.routeInformationProvider.value.uri.toString(),
  );

  bool _isOnRoute(String route) =>
      _currentRoute() == AppRoutes.canonicalRoute(route);

  Future<void> _handleOverlayRouteChange() async {
    final targetRoute = widget.overlayTargetRoute;
    if (targetRoute == null || !mounted || _isOnRoute(targetRoute)) {
      return;
    }

    _routeMovedExternally = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await Navigator.of(context).maybePop();
    });
  }

  /// The editor's own way out when nothing was pushed underneath it.
  ///
  /// [AppBar] implies a back button only when the navigator can pop, so a sheet
  /// reached by deep link or a pasted URL had no way out at all except the
  /// browser's, which walked to whatever sat before the app. Returning null
  /// leaves every other entry point — the sheets list, a search hit, the file
  /// browser's overlay — on the implied button, and their existing pop
  /// handling (#1749).
  Widget? _backButton() => Navigator.of(context).canPop()
      ? null
      : BackButton(
          onPressed: () =>
              context.go(AppRoutes.containingFolder(widget.filePath)),
        );

  void _restoreOverlayCloseRoute() {
    final targetRoute = widget.overlayTargetRoute;
    final closeRoute = widget.overlayCloseRoute;
    if (targetRoute == null || closeRoute == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_routeMovedExternally && _isOnRoute(targetRoute)) {
        router.go(closeRoute);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    if (widget.overlayTargetRoute != null) {
      router.routeInformationProvider.addListener(_handleOverlayRouteChange);
    }
    _loadFile();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    if (widget.overlayTargetRoute != null) {
      router.routeInformationProvider.removeListener(_handleOverlayRouteChange);
    }
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

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.filePath.split('/').last;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          leading: _backButton(),
          title: Text(title),
          actions: const [AppThemeToggle()],
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final error = _error;
    if (error != null) {
      return Scaffold(
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
    }

    final tab = _tabs[_selected];

    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          _restoreOverlayCloseRoute();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _backButton(),
          title: Text(title),
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
      ),
    );
  }
}
