import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/content_result_tile.dart';
import 'package:quark/widgets/sheets/sheet_tile.dart';
import 'package:quark/widgets/docs/doc_tile.dart';
import 'package:quark/widgets/search_section_header.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the docs search bar: the load state, the docs whose
/// name matches, the docs whose content matches, and then an "In Sheets"
/// section with the sheets that match either way (#2259).
class DocsBody extends StatelessWidget {
  final bool loading;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;
  final List<FileNode> files;

  /// The sheets whose name matches the search, for the "In Sheets"
  /// section. Only shown while searching.
  final List<FileNode> sheetFiles;

  /// Every content hit, of any type. Each is sorted into this page's section
  /// or the "In Sheets" one by its extension; anything else is left out,
  /// since neither editor can open it.
  final List<ContentSearchResult> contentResults;
  final bool contentSearching;

  /// The raw search text, so the empty state can tell "no docs yet" from
  /// "nothing matched".
  final String searchQuery;
  final VoidCallback onRetry;
  final VoidCallback onCreateNew;
  final ValueChanged<FileNode> onOpenDoc;
  final ValueChanged<FileNode> onOpenSheet;

  const DocsBody({
    required this.loading,
    required this.error,
    required this.files,
    required this.sheetFiles,
    required this.contentResults,
    required this.contentSearching,
    required this.searchQuery,
    required this.onRetry,
    required this.onCreateNew,
    required this.onOpenDoc,
    required this.onOpenSheet,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = this.error;
    if (error != null) {
      if (isQuarkUnreachableError(error)) {
        return QuarkDisconnectedView(
          hostAddress: AppSettings.instance.activeHost,
          onRetry: onRetry,
          onManageHosts: () => context.go(AppRoutes.settings),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(QuarkIcons.error_outline, size: 40, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              Errors.message(error, 'load your documents'),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
    }
    // Content matches are rendered by the list, so the empty state must
    // account for them too. Checking only the filename matches here would
    // short-circuit every content-only search — the common case, since a query
    // that matches a document's text usually does not also match its filename.
    // The same goes for the other type's section (#2259). The guard and the
    // list read the same lists so they cannot disagree about whether there is
    // anything to show.
    final isSearching = searchQuery.isNotEmpty;
    final ownContent = isSearching
        ? contentResults
              .where((r) => ContentResultTile.isDoc(r.relPath))
              .toList()
        : const <ContentSearchResult>[];
    final otherContent = isSearching
        ? contentResults
              .where((r) => ContentResultTile.isSheet(r.relPath))
              .toList()
        : const <ContentSearchResult>[];
    final otherFiles = isSearching ? sheetFiles : const <FileNode>[];
    final hasOther = otherFiles.isNotEmpty || otherContent.isNotEmpty;

    if (files.isEmpty && ownContent.isEmpty && !hasOther) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              QuarkIcons.description_outlined,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              isSearching ? 'No docs match your search.' : 'No docs yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            if (contentSearching) ...const [
              SizedBox(height: 16),
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ],
            const SizedBox(height: 16),
            // Offered while searching too (#2044). A search that found
            // nothing is the moment someone knows exactly what they wanted
            // and does not have it — sending them back to a toolbar icon to
            // start it is the long way round.
            FilledButton.icon(
              key: const ValueKey('docs_create_cta'),
              onPressed: onCreateNew,
              icon: const Icon(Icons.add),
              label: Text(
                isSearching ? 'Create a new doc instead' : 'Create new doc',
              ),
            ),
          ],
        ),
      );
    }

    // Built up front but laid out lazily by the builder.
    final items = <Widget>[
      for (final node in files)
        DocTile(node: node, onTap: () => onOpenDoc(node)),
      if (ownContent.isNotEmpty)
        const SearchSectionHeader(
          icon: QuarkIcons.search_rounded,
          label: 'Content matches',
        ),
      for (final result in ownContent) ContentResultTile(result: result),
      if (hasOther)
        const SearchSectionHeader(
          icon: QuarkIcons.table_chart_outlined,
          label: 'In Sheets',
        ),
      for (final node in otherFiles)
        SheetTile(node: node, onTap: () => onOpenSheet(node)),
      for (final result in otherContent) ContentResultTile(result: result),
    ];

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}
