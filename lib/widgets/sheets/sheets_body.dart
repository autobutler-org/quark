import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/utils/connection_error.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/sheets/sheet_content_result_tile.dart';
import 'package:quark/widgets/sheets/sheet_tile.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the sheets search bar: the load state, the filename
/// matches, and the content matches below them.
class SheetsBody extends StatelessWidget {
  final bool loading;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  final Object? error;
  final List<FileNode> files;
  final List<ContentSearchResult> contentResults;
  final bool contentSearching;

  /// The raw search text, so the empty state can tell "no sheets yet" from
  /// "nothing matched".
  final String searchQuery;
  final VoidCallback onRetry;
  final VoidCallback onCreateNew;
  final ValueChanged<FileNode> onOpenSheet;

  const SheetsBody({
    required this.loading,
    required this.error,
    required this.files,
    required this.contentResults,
    required this.contentSearching,
    required this.searchQuery,
    required this.onRetry,
    required this.onCreateNew,
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
              Errors.message(error, 'load your sheets'),
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
    // that matches a sheet's contents usually does not also match its
    // filename. Both the guard and the list read the same flag so they cannot
    // disagree about whether there is anything to show.
    final hasContentResults =
        searchQuery.isNotEmpty && contentResults.isNotEmpty;

    if (files.isEmpty && !hasContentResults) {
      final isSearching = searchQuery.isNotEmpty;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              QuarkIcons.table_chart_outlined,
              size: 48,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 12),
            Text(
              isSearching ? 'No sheets match your search.' : 'No sheets yet.',
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
              key: const ValueKey('sheets_create_cta'),
              onPressed: onCreateNew,
              icon: const Icon(Icons.add),
              label: Text(
                isSearching ? 'Create a new sheet instead' : 'Create new sheet',
              ),
            ),
          ],
        ),
      );
    }

    final totalItems =
        files.length + (hasContentResults ? contentResults.length + 1 : 0);

    return ListView.builder(
      itemCount: totalItems,
      itemBuilder: (context, i) {
        if (i < files.length) {
          final node = files[i];
          return SheetTile(node: node, onTap: () => onOpenSheet(node));
        }
        final ci = i - files.length;
        if (ci == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Icon(
                  QuarkIcons.search_rounded,
                  size: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                Text(
                  'Content matches',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          );
        }
        return SheetContentResultTile(result: contentResults[ci - 1]);
      },
    );
  }
}
