import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/doc_sheet_listing_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
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

/// The Docs page: the user's `.qdoc` documents, with a way to start a new one.
/// A search also matches document contents and lists the sheets whose names
/// match. Its state is a [DocSheetListingController], shared with Sheets.
class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  final _controller = DocSheetListingController(
    fileType: 'qdoc',
    otherType: 'qsheet',
    emptyFile: '{"ops":[{"insert":"\\n"}]}',
  );
  final _search = TextEditingController();

  @override
  void initState() {
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
      from: AppRoutes.docs,
    ),
  );

  void _openSheet(FileNode node) => context.go(
    AppRoutes.sheetFile(
      node.apiPath,
      serial: node.deviceSerial,
      from: AppRoutes.docs,
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

  Future<void> _create() async {
    final name = await promptForNewFileName(
      context,
      title: 'New Document',
      hintText: 'Document name',
    );
    if (name == null || name.isEmpty || !mounted) return;
    try {
      final path = await _controller.create(name);
      if (mounted) {
        context.go(AppRoutes.docFile(path, from: AppRoutes.docs), extra: true);
      }
    } catch (e) {
      if (!mounted) return;
      showMessage(context, Errors.upload(e, 'create the document'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: 'Docs',
      icon: QuarkIcons.description_outlined,
      onRefresh: manualRefresh,
      isRefreshing: isRefreshing,
      actions: [
        QuarkBarChip(
          key: const ValueKey('docs_new'),
          icon: QuarkIcons.add_rounded,
          label: 'New document',
          onPressed: _create,
        ),
        const AppThemeToggle(),
      ],
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.docs),
      body: Column(
        children: [
          FileTypeSearchBar(
            controller: _search,
            hintText: 'Search docs…',
            keyPrefix: 'docs',
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: _controller,
              builder: (context, _) => DocSheetBody(
                kind: DocSheetKind.docs,
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
              ),
            ),
          ),
        ],
      ),
    );
  }
}
