import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import 'code_language.dart';
import 'code_search_match.dart';
import 'quark_code_viewer/code_viewer_body.dart';
import 'quark_code_viewer/code_viewer_toolbar.dart';

/// A read-only viewer for a text file: line numbers, syntax highlighting,
/// search, and a choice between wrapping long lines and scrolling sideways.
///
/// It shows what it is given. The caller owns the lines, the search query and
/// its hits (`findCodeMatches` computes them), which hit is active, and
/// whether lines wrap; every control reports through a callback and changes
/// nothing by itself. A large file arrives in parts: the caller appends to
/// [lines], sets [hasMore] while the server holds more, and loads the next
/// part when [onLoadMore] fires, which it does as the list nears its end.
///
/// States: a loader while [isLoading]; [error] with a Retry button; "Empty
/// file" when there are no lines and no more to load; otherwise the text.
/// The toolbar stays in place through all of them.
///
/// The viewer fills the space it is given, so give it a bounded height: an
/// `Expanded`, a page body, a `SizedBox`.
///
/// Key prefixes: `code_viewer_search_field`, `code_viewer_search_previous`,
/// `code_viewer_search_next`, `code_viewer_wrap_toggle`,
/// `code_viewer_match_count`, `code_viewer_status`, `code_viewer_retry`,
/// `code_viewer_load_more`, and `code_viewer_line_<index>` on each line, with
/// a 0-based index.
///
/// ```dart
/// QuarkCodeViewer(
///   lines: controller.lines,
///   language: codeLanguageFor('main.dart'),
///   wrap: controller.wrap,
///   onWrapChanged: controller.setWrap,
///   searchQuery: controller.query,
///   onSearchChanged: controller.search,
///   matches: controller.matches,
///   activeMatch: controller.activeMatch,
///   onNextMatch: controller.nextMatch,
///   onPreviousMatch: controller.previousMatch,
///   hasMore: controller.hasMore,
///   isLoadingMore: controller.isLoadingMore,
///   onLoadMore: controller.loadMore,
/// );
/// ```
class QuarkCodeViewer extends StatefulWidget {
  /// Creates a viewer showing [lines].
  const QuarkCodeViewer({
    required this.lines,
    this.language = CodeLanguage.plain,
    this.isLoading = false,
    this.error,
    this.onRetry,
    this.wrap = false,
    this.onWrapChanged,
    this.searchQuery = '',
    this.onSearchChanged,
    this.matches = const [],
    this.activeMatch,
    this.onNextMatch,
    this.onPreviousMatch,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.loadMoreError,
    this.onLoadMore,
    this.statusLabel,
    super.key,
  });

  /// The file's lines, without trailing newlines. Append-only as more of the
  /// file loads; a list that is not an extension of the last one is treated
  /// as a different file.
  final List<String> lines;

  /// The language to color [lines] in. `codeLanguageFor` picks one from a
  /// file name.
  final CodeLanguage language;

  /// Whether the file is loading for the first time, which shows a loader in
  /// place of the text.
  final bool isLoading;

  /// Why the file could not be loaded, rendered as given in place of the
  /// text; null when it loaded. The caller composes the sentence.
  final String? error;

  /// Called when Retry is tapped under [error]. Null leaves the button out.
  final VoidCallback? onRetry;

  /// Whether a line too long for the width wraps instead of scrolling
  /// sideways.
  final bool wrap;

  /// Called with the opposite of [wrap] when the wrap toggle is tapped. Null
  /// disables the toggle.
  final ValueChanged<bool>? onWrapChanged;

  /// The search query. The field follows it when the caller changes it.
  final String searchQuery;

  /// Called with the field's text on every edit. Null disables the field.
  final ValueChanged<String>? onSearchChanged;

  /// The hits for [searchQuery] in [lines], in line order, computed by the
  /// caller. Each is painted on a tinted background.
  final List<CodeSearchMatch> matches;

  /// The index into [matches] of the hit the search is on: drawn strongest,
  /// counted in the toolbar, and scrolled into view when it changes. Null
  /// before a hit is picked.
  final int? activeMatch;

  /// Called by the next button and by Enter in the search field.
  final VoidCallback? onNextMatch;

  /// Called by the previous button.
  final VoidCallback? onPreviousMatch;

  /// Whether more of the file is still on the server. Shows the footer under
  /// the last line and marks the match counter as covering only what is
  /// loaded.
  final bool hasMore;

  /// Whether the next part is being loaded, which shows a loader in the
  /// footer and holds [onLoadMore] back.
  final bool isLoadingMore;

  /// Why loading the next part failed, rendered as given in the footer beside
  /// a Retry button; null when it did not. While set, scrolling does not call
  /// [onLoadMore].
  final String? loadMoreError;

  /// Called to load the next part: when the list scrolls within a viewport
  /// of its end, once for each length of [lines], and when the footer's
  /// button is tapped.
  final VoidCallback? onLoadMore;

  /// A line about the file, such as "Showing 256 KB of 1.2 GB", shown in the
  /// toolbar; null shows nothing.
  final String? statusLabel;

  @override
  State<QuarkCodeViewer> createState() => _QuarkCodeViewerState();
}

class _QuarkCodeViewerState extends State<QuarkCodeViewer> {
  late final TextEditingController _search = TextEditingController(
    text: widget.searchQuery,
  );

  @override
  void didUpdateWidget(QuarkCodeViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only when the caller moved the query: an unchanged one that trails the
    // field, while the caller debounces, must not undo what was just typed.
    final query = widget.searchQuery;
    if (query != oldWidget.searchQuery && query != _search.text) {
      _search.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.error;
    final onRetry = widget.onRetry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CodeViewerToolbar(
          searchController: _search,
          searchQuery: widget.searchQuery,
          onSearchChanged: widget.onSearchChanged,
          matchCount: widget.matches.length,
          activeMatch: widget.activeMatch,
          onNextMatch: widget.onNextMatch,
          onPreviousMatch: widget.onPreviousMatch,
          wrap: widget.wrap,
          onWrapChanged: widget.onWrapChanged,
          hasMore: widget.hasMore,
          statusLabel: widget.statusLabel,
        ),
        Expanded(
          child: widget.isLoading
              ? const Center(child: QuarkLoader())
              : error != null
              ? EmptyStateWidget(
                  icon: QuarkIcons.error_outline,
                  headline: error,
                  action: onRetry == null
                      ? null
                      : FilledButton(
                          key: const ValueKey('code_viewer_retry'),
                          onPressed: onRetry,
                          child: const Text('Retry'),
                        ),
                )
              : widget.lines.isEmpty && !widget.hasMore
              ? const EmptyStateWidget(
                  icon: QuarkIcons.description_outlined,
                  headline: 'Empty file',
                )
              : CodeViewerBody(
                  lines: widget.lines,
                  language: widget.language,
                  wrap: widget.wrap,
                  matches: widget.matches,
                  activeMatch: widget.activeMatch,
                  hasMore: widget.hasMore,
                  isLoadingMore: widget.isLoadingMore,
                  loadMoreError: widget.loadMoreError,
                  onLoadMore: widget.onLoadMore,
                ),
        ),
      ],
    );
  }
}
