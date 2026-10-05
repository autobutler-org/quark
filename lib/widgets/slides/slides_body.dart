import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/content_search_service.dart';
import 'package:quark/widgets/content_result_tile.dart';
import 'package:quark/widgets/doc_sheet_tile.dart';
import 'package:quark/widgets/search_section_header.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the Slides search bar: the load state, the presentations
/// whose name matches, then those whose contents match.
///
/// A file that matched by name and by content is listed once, in the name
/// rows, with the content hit's snippet, as on Docs and Sheets (#2272). The
/// empty state offers to create a presentation whether or not a search is
/// running (#2044).
///
/// Key prefixes: `slides_create_cta` on the empty state's create button, and
/// [DocSheetTile]'s on each row.
class SlidesBody extends StatelessWidget {
  /// Shows [files] and [contentResults] for [searchQuery].
  const SlidesBody({
    required this.loading,
    required this.error,
    required this.files,
    required this.contentResults,
    required this.contentSearching,
    required this.searchQuery,
    required this.onRetry,
    required this.onCreateNew,
    required this.onOpen,
    this.onRename,
    this.onShare,
    super.key,
  });

  /// Whether the first listing is still on its way, with nothing to show.
  final bool loading;

  /// The thrown object from the last refresh, not its message —
  /// [SlidesErrorView] decides what it means (#1637).
  final Object? error;

  /// The presentations whose name matches the search; all of them with none.
  final List<FileNode> files;

  /// Presentations whose contents match the search.
  final List<ContentSearchResult> contentResults;

  /// Whether the content search is still running.
  final bool contentSearching;

  /// The search text, so the empty state can tell "none yet" from "nothing
  /// matched".
  final String searchQuery;

  /// Called by the error view's retry button.
  final VoidCallback onRetry;

  /// Called by the empty state's create button.
  final VoidCallback onCreateNew;

  /// Called with the presentation tapped.
  final ValueChanged<FileNode> onOpen;

  /// Renames a listed presentation. Content-only hits carry no [FileNode],
  /// so their rows have no menu.
  final ValueChanged<FileNode>? onRename;

  /// Opens the share sheet for a listed presentation (#1170); content-only
  /// hits have no menu.
  final ValueChanged<FileNode>? onShare;

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: QuarkLoader());
    final error = this.error;
    if (error != null) {
      return SlidesErrorView(
        error: error,
        action: 'load your presentations',
        onRetry: onRetry,
      );
    }

    final isSearching = searchQuery.trim().isNotEmpty;
    final listed = {
      for (final node in files)
        DocSheetTile.fileKey(node.deviceSerial, node.apiPath),
    };
    final hits = isSearching ? contentResults : const <ContentSearchResult>[];
    final snippets = {
      for (final r in hits)
        DocSheetTile.fileKey(r.deviceSerial, r.relPath): r.plainSnippet,
    };
    final contentOnly = [
      for (final r in hits)
        if (!listed.contains(DocSheetTile.fileKey(r.deviceSerial, r.relPath)))
          r,
    ];

    if (files.isEmpty && contentOnly.isEmpty) {
      return EmptyStateWidget(
        icon: QuarkIcons.slideshow_outlined,
        headline: isSearching
            ? 'No presentations match your search'
            : 'No presentations yet',
        subtext: contentSearching ? 'Searching inside presentations…' : null,
        action: FilledButton.icon(
          key: const ValueKey('slides_create_cta'),
          onPressed: onCreateNew,
          icon: const Icon(QuarkIcons.add_rounded),
          label: Text(
            isSearching
                ? 'Create a new presentation instead'
                : 'Create a presentation',
          ),
        ),
      );
    }

    // The device name only tells rows apart when they span more than one
    // device (#2272).
    final serials = {
      for (final node in files) node.deviceSerial,
      for (final r in contentOnly) r.deviceSerial,
    };
    final showDevice = serials.length > 1;
    final deviceNames = {
      for (final node in files) node.deviceSerial: node.deviceName,
    };
    final onRename = this.onRename;
    final onShare = this.onShare;

    final items = <Widget>[
      for (final node in files)
        DocSheetTile(
          relPath: node.apiPath,
          deviceName: node.deviceName,
          showDevice: showDevice,
          snippet:
              snippets[DocSheetTile.fileKey(node.deviceSerial, node.apiPath)],
          onTap: () => onOpen(node),
          onRename: onRename == null ? null : () => onRename(node),
          onShare: onShare == null ? null : () => onShare(node),
        ),
      if (contentOnly.isNotEmpty)
        const SearchSectionHeader(
          icon: QuarkIcons.search_rounded,
          label: 'Content matches',
        ),
      for (final r in contentOnly)
        ContentResultTile(
          result: r,
          deviceName: deviceNames[r.deviceSerial] ?? '',
          showDevice: showDevice,
        ),
    ];
    return ListView.builder(
      itemCount: items.length,
      itemBuilder: (context, i) => items[i],
    );
  }
}
