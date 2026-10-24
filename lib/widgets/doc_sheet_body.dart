import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/content_result_tile.dart';
import 'package:quark/widgets/doc_sheet_kind.dart';
import 'package:quark/widgets/doc_sheet_tile.dart';
import 'package:quark/widgets/search_section_header.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the Docs or Sheets search bar, as [kind] says: the load
/// state, the files of that type whose name matches, those whose content
/// matches, and then an "In Sheets" or "In Docs" section with the other
/// type's files that match either way (#2259).
///
/// Key prefixes: `docs_create_cta` or `sheets_create_cta` on the empty
/// state's create button, and [DocSheetTile]'s on each row.
class DocSheetBody extends StatelessWidget {
  /// Which page this is on.
  final DocSheetKind kind;

  /// Whether the first listing is still on its way, with nothing to show.
  final bool loading;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;

  /// The [kind] files whose name matches the search; all of them with none.
  final List<FileNode> files;

  /// The other type's files whose name matches the search, for its section.
  /// Only shown while searching.
  final List<FileNode> otherFiles;

  /// Every content hit, of any type. Each is sorted into this page's section
  /// or the other type's by its extension; anything else is left out,
  /// since neither editor can open it.
  final List<ContentSearchResult> contentResults;

  /// Whether the content search is still running.
  final bool contentSearching;

  /// The raw search text, so the empty state can tell "none yet" from
  /// "nothing matched".
  final String searchQuery;

  /// Called by the error view's retry button.
  final VoidCallback onRetry;

  /// Called by the empty state's create button.
  final VoidCallback onCreateNew;

  /// Called with a doc tapped, on either page.
  final ValueChanged<FileNode> onOpenDoc;

  /// Called with a sheet tapped, on either page.
  final ValueChanged<FileNode> onOpenSheet;

  /// Renames a listed file. Content-only hits carry no [FileNode], so their
  /// rows have no menu.
  final ValueChanged<FileNode>? onRename;

  /// Shows [files], [otherFiles] and [contentResults] for [searchQuery].
  const DocSheetBody({
    required this.kind,
    required this.loading,
    required this.error,
    required this.files,
    required this.otherFiles,
    required this.contentResults,
    required this.contentSearching,
    required this.searchQuery,
    required this.onRetry,
    required this.onCreateNew,
    required this.onOpenDoc,
    required this.onOpenSheet,
    this.onRename,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (loading) {
      return const Center(child: QuarkLoader());
    }
    final error = this.error;
    if (error != null) {
      if (isQuarkUnreachableError(error)) {
        return QuarkDisconnectedView(
          hostAddress: AppSettings.instance.activeHost,
          onRetry: onRetry,
          onManageHosts: () =>
              context.go(AppRoutes.settingsTab(SettingsTab.general)),
        );
      }
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(QuarkIcons.error_outline, size: 40, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              Errors.message(error, kind.loadAction),
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
    // that matches a file's text usually does not also match its filename.
    // The same goes for the other type's section (#2259). The guard and the
    // list read the same lists so they cannot disagree about whether there is
    // anything to show.
    final isSearching = searchQuery.isNotEmpty;
    final otherFiles = isSearching ? this.otherFiles : const <FileNode>[];
    // A file that matched by name and by content is listed once, in the
    // filename rows, carrying the content hit's snippet (#2272).
    final listed = {
      for (final node in [...files, ...otherFiles])
        DocSheetTile.fileKey(node.deviceSerial, node.apiPath),
    };
    final hits = isSearching ? contentResults : const <ContentSearchResult>[];
    final snippets = {
      for (final r in hits)
        DocSheetTile.fileKey(r.deviceSerial, r.relPath): r.plainSnippet,
    };
    final contentOnly = hits
        .where(
          (r) =>
              !listed.contains(DocSheetTile.fileKey(r.deviceSerial, r.relPath)),
        )
        .toList();
    final ownContent = contentOnly.where((r) => kind.owns(r.relPath)).toList();
    final otherContent = contentOnly
        .where((r) => kind.other.owns(r.relPath))
        .toList();
    final hasOther = otherFiles.isNotEmpty || otherContent.isNotEmpty;

    if (files.isEmpty && ownContent.isEmpty && !hasOther) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              kind.icon,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              isSearching
                  ? 'No ${kind.noun}s match your search.'
                  : 'No ${kind.noun}s yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            if (contentSearching) ...const [
              SizedBox(height: 16),
              QuarkLoader(size: 20),
            ],
            const SizedBox(height: 16),
            // Offered while searching too (#2044). A search that found
            // nothing is the moment someone knows exactly what they wanted
            // and does not have it — sending them back to a toolbar icon to
            // start it is the long way round.
            FilledButton.icon(
              key: ValueKey('${kind.name}_create_cta'),
              onPressed: onCreateNew,
              icon: const Icon(Icons.add),
              label: Text(
                isSearching
                    ? 'Create a new ${kind.noun} instead'
                    : 'Create new ${kind.noun}',
              ),
            ),
          ],
        ),
      );
    }

    // The device name only tells rows apart when they span more than one
    // device; on a single-storage Quark it would repeat on every row (#2272).
    final serials = {
      for (final node in [...files, ...otherFiles]) node.deviceSerial,
      for (final r in [...ownContent, ...otherContent]) r.deviceSerial,
    };
    final showDevice = serials.length > 1;
    // A content hit carries only a serial, so its device name comes from a
    // filename match on the same device; with none, the row shows the folder.
    final deviceNames = {
      for (final node in [...files, ...otherFiles])
        node.deviceSerial: node.deviceName,
    };
    final onRename = this.onRename;
    final openOwn = kind == DocSheetKind.docs ? onOpenDoc : onOpenSheet;
    final openOther = kind == DocSheetKind.docs ? onOpenSheet : onOpenDoc;
    DocSheetTile nodeTile(FileNode node, VoidCallback onTap) => DocSheetTile(
      relPath: node.apiPath,
      deviceName: node.deviceName,
      showDevice: showDevice,
      snippet: snippets[DocSheetTile.fileKey(node.deviceSerial, node.apiPath)],
      onTap: onTap,
      onRename: onRename == null ? null : () => onRename(node),
    );
    ContentResultTile hitTile(ContentSearchResult r) => ContentResultTile(
      result: r,
      deviceName: deviceNames[r.deviceSerial] ?? '',
      showDevice: showDevice,
    );

    // Built up front but laid out lazily by the builder.
    final items = <Widget>[
      for (final node in files) nodeTile(node, () => openOwn(node)),
      if (ownContent.isNotEmpty)
        const SearchSectionHeader(
          icon: QuarkIcons.search_rounded,
          label: 'Content matches',
        ),
      for (final result in ownContent) hitTile(result),
      if (hasOther)
        SearchSectionHeader(
          icon: kind.other.icon,
          label: kind.other.sectionLabel,
        ),
      for (final node in otherFiles) nodeTile(node, () => openOther(node)),
      for (final result in otherContent) hitTile(result),
    ];

    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}
