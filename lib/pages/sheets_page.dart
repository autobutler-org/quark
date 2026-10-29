import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/doc_sheet_listing_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/delete_doc_sheet.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/rename_doc_sheet.dart';
import 'package:quark/widgets/doc_sheet_body.dart';
import 'package:quark/widgets/doc_sheet_kind.dart';
import 'package:quark/widgets/file_type_search_bar.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Sheets page: the user's `.qsheet` spreadsheets, with a way to start a
/// new one. A search also matches sheet contents and lists the docs whose
/// names match. Its state is a [DocSheetListingController], shared with Docs.
class SheetsPage extends StatefulWidget {
  const SheetsPage({super.key});

  @override
  State<SheetsPage> createState() => _SheetsPageState();
}

class _SheetsPageState extends State<SheetsPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  final _controller = DocSheetListingController(
    fileType: 'qsheet',
    otherType: 'qdoc',
    emptyFile: '{"tabs":[{"name":"Sheet 1","data":{"columns":[],"rows":[]}}]}',
  );
  final _search = TextEditingController();
  late final Listenable _listing;

  @override
  void initState() {
    _listing = Listenable.merge([_controller, AppSettings.instance.isAdmin]);
    super.initState();
    _search.addListener(() => _controller.setQuery(_search.text));
  }

  @override
  void dispose() {
    _search.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _openDoc(FileNode node) => context.go(
    AppRoutes.docFile(
      node.apiPath,
      serial: node.deviceSerial,
      from: AppRoutes.sheets,
    ),
  );

  void _openSheet(FileNode node) => context.go(
    AppRoutes.sheetFile(
      node.apiPath,
      serial: node.deviceSerial,
      from: AppRoutes.sheets,
    ),
  );

  Future<void> _rename(FileNode node) async {
    final renamed = await renameDocOrSheet(
      context,
      node,
      siblings: _controller.siblings,
    );
    if (renamed != null) manualRefresh();
  }

  Future<void> _delete(FileNode node) async {
    if (await deleteDocOrSheet(context, node)) manualRefresh();
  }

  Future<void> _create() async {
    final name = await promptForNewFileName(
      context,
      title: 'New Spreadsheet',
      hintText: 'Spreadsheet name',
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final path = await _controller.create(name);
      if (mounted) {
        context.go(AppRoutes.sheetFile(path, from: AppRoutes.sheets));
      }
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.upload(e, 'create the sheet'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: 'Sheets',
      icon: QuarkIcons.table_chart_outlined,
      onRefresh: manualRefresh,
      isRefreshing: isRefreshing,
      actions: [
        QuarkBarChip(
          key: const ValueKey('sheets_new'),
          icon: QuarkIcons.add_rounded,
          label: 'New spreadsheet',
          onPressed: _create,
        ),
        const AppThemeToggle(),
      ],
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.sheets),
      body: Column(
        children: [
          FileTypeSearchBar(
            controller: _search,
            hintText: 'Search sheets…',
            keyPrefix: 'sheets',
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _listing,
              builder: (context, _) => DocSheetBody(
                kind: DocSheetKind.sheets,
                loading: isInitialLoad && !_controller.hasListing,
                error: _controller.error,
                files: _controller.filtered,
                otherFiles: _controller.otherFiltered,
                contentResults: _controller.contentResults,
                contentSearching: _controller.contentSearching,
                searchQuery: _controller.query,
                onRetry: manualRefresh,
                onCreateNew: _create,
                onOpenDoc: _openDoc,
                onOpenSheet: _openSheet,
                onRename: _rename,
                onDelete: _delete,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
