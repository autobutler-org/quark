import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/rename_doc_sheet.dart';
import 'package:quark/utils/safe_set_state_mixin.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:quark/widgets/docs/docs_body.dart';
import 'package:quark/widgets/docs/docs_search_bar.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';

/// The Docs page: the user's `.qdoc` documents, with a way to start a new one. A search also matches document
/// contents and lists the sheets whose names match.
class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage>
    with SafeSetStateMixin, WidgetsBindingObserver, AutoRefreshMixin {
  List<FileNode> _files = [];
  List<FileNode> _filtered = [];

  /// Every sheet, so a search can list the ones that match in an
  /// "In Sheets" section (#2259).
  List<FileNode> _sheets = [];
  List<FileNode> _sheetsFiltered = [];
  List<ContentSearchResult> _contentResults = [];
  bool _contentSearching = false;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;
  final _searchController = TextEditingController();
  Timer? _contentSearchDebounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _contentSearchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() async {
    try {
      final results = await Future.wait([
        FilesService.getFilesByType('qdoc'),
        FilesService.getFilesByType('qsheet'),
      ]);
      setStateSafely(() {
        _files = results[0];
        _sheets = results[1];
        _applyFilter();
        // Cleared on success rather than up front, so a poll against an
        // unreachable Quark does not blink the error view away and back.
        _error = null;
      });
    } catch (e) {
      setStateSafely(() {
        _error = e;
      });
    }
  }

  void _onSearchChanged() {
    _applyFilter();
    _contentSearchDebounce?.cancel();
    final q = _searchController.text.trim();
    if (q.isEmpty) {
      setStateSafely(() {
        _contentResults = [];
        _contentSearching = false;
      });
      return;
    }
    setStateSafely(() => _contentSearching = true);
    _contentSearchDebounce = Timer(const Duration(milliseconds: 400), () async {
      final results = await ContentSearchService.search(q);
      setStateSafely(() {
        _contentResults = results;
        _contentSearching = false;
      });
    });
  }

  void _applyFilter() {
    final query = _searchController.text.trim().toLowerCase();
    bool matches(FileNode f) => f.matchesSearch(query);
    setStateSafely(() {
      _filtered = query.isEmpty
          ? List.of(_files)
          : _files.where(matches).toList();
      // The other type only appears as search results, never as the library.
      _sheetsFiltered = query.isEmpty ? [] : _sheets.where(matches).toList();
    });
  }

  void _openDoc(FileNode node) =>
      context.go(AppRoutes.docFile(node.apiPath, serial: node.deviceSerial));

  void _openSheet(FileNode node) =>
      context.go(AppRoutes.sheetFile(node.apiPath, serial: node.deviceSerial));

  Future<void> _renameFile(FileNode node) async {
    final renamed = await renameDocOrSheet(
      context,
      node,
      siblings: [..._files, ..._sheets],
    );
    if (renamed != null) manualRefresh();
  }

  Future<void> _createNewDoc() async {
    final name = await promptForNewFileName(
      context,
      title: 'New Document',
      hintText: 'Document name',
    );
    if (name == null || name.isEmpty || !mounted) return;

    try {
      final fileName = name.endsWith('.qdoc') ? name : '$name.qdoc';
      final bytes = '{"ops":[{"insert":"\\n"}]}'.codeUnits;
      final file = http.MultipartFile.fromBytes(
        'files',
        bytes,
        filename: fileName,
      );
      await FilesService.uploadFilesFromFormData('', [file]);
      if (!mounted) return;
      context.go(AppRoutes.docFile(fileName), extra: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.upload(e, 'create the document'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: QuarkAppBar(
        label: 'Docs',
        icon: QuarkIcons.description_outlined,
        onRefresh: manualRefresh,
        isRefreshing: isRefreshing,
        actions: [
          QuarkBarChip(
            key: const ValueKey('docs_new'),
            icon: QuarkIcons.add_rounded,
            label: 'New document',
            onPressed: _createNewDoc,
          ),
          const AppThemeToggle(),
        ],
      ),
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.docs),
      body: Column(
        children: [
          DocsSearchBar(controller: _searchController),
          Expanded(
            child: DocsBody(
              loading: isInitialLoad,
              error: _error,
              files: _filtered,
              sheetFiles: _sheetsFiltered,
              contentResults: _contentResults,
              contentSearching: _contentSearching,
              searchQuery: _searchController.text,
              onRetry: manualRefresh,
              onCreateNew: _createNewDoc,
              onOpenDoc: _openDoc,
              onOpenSheet: _openSheet,
              onRename: _renameFile,
            ),
          ),
        ],
      ),
    );
  }
}
