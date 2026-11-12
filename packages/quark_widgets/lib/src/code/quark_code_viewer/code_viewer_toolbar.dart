import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';

import '../../layout/quark_bar_icon_button.dart';
import '../../theme/quark_tokens.dart';

/// The bar above a `QuarkCodeViewer`'s text: a search field with previous and
/// next buttons, a wrap toggle, and under them a match counter and the
/// caller's [statusLabel].
///
/// The counter reads "3 of 17" on a hit, "17 results" before one is picked,
/// and "No results" on a miss. With [hasMore] it says the search only covered
/// what is loaded: "3 of 17 loaded", "No results in the loaded part".
///
/// The field and the three buttons share one row at any width; the counter
/// and the status wrap under it, so nothing is squeezed on a phone or at a
/// large text size.
///
/// Key prefixes: `code_viewer_search_field`, `code_viewer_search_previous`,
/// `code_viewer_search_next`, `code_viewer_wrap_toggle`,
/// `code_viewer_match_count` and `code_viewer_status`.
///
/// ```dart
/// CodeViewerToolbar(
///   searchController: searchController,
///   searchQuery: controller.query,
///   onSearchChanged: controller.search,
///   matchCount: controller.matches.length,
///   activeMatch: controller.activeMatch,
///   onNextMatch: controller.nextMatch,
///   onPreviousMatch: controller.previousMatch,
///   wrap: controller.wrap,
///   onWrapChanged: controller.setWrap,
/// );
/// ```
class CodeViewerToolbar extends StatelessWidget {
  /// Creates the toolbar.
  const CodeViewerToolbar({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.matchCount,
    required this.activeMatch,
    required this.onNextMatch,
    required this.onPreviousMatch,
    required this.wrap,
    required this.onWrapChanged,
    this.hasMore = false,
    this.statusLabel,
    super.key,
  });

  /// Holds the search field's text. The viewer owns it and keeps it in step
  /// with its `searchQuery`.
  final TextEditingController searchController;

  /// The query the hits were found for, which the counter describes. It can
  /// trail the field's text while the caller is still searching.
  final String searchQuery;

  /// Called with the field's text on every edit. Null disables the field.
  final ValueChanged<String>? onSearchChanged;

  /// How many hits the search has.
  final int matchCount;

  /// The index of the hit the search is on, or null before one is picked.
  final int? activeMatch;

  /// Called by the next button and by Enter in the field.
  final VoidCallback? onNextMatch;

  /// Called by the previous button.
  final VoidCallback? onPreviousMatch;

  /// Whether long lines wrap, shown as the toggle's selected state.
  final bool wrap;

  /// Called with the opposite of [wrap] when the toggle is tapped. Null
  /// disables the toggle.
  final ValueChanged<bool>? onWrapChanged;

  /// Whether more of the file is still on the server, in which case the
  /// counter says it only counted what is loaded.
  final bool hasMore;

  /// A line about the file, such as "Showing 256 KB of 1.2 GB", shown beside
  /// the counter; null shows nothing.
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final active = activeMatch;
    final String counter;
    if (searchQuery.isEmpty) {
      counter = '';
    } else if (matchCount == 0) {
      counter = hasMore ? 'No results in the loaded part' : 'No results';
    } else {
      final count = active == null
          ? (matchCount == 1 ? '1 result' : '$matchCount results')
          : '${active + 1} of $matchCount';
      counter = hasMore ? '$count loaded' : count;
    }
    final status = statusLabel;
    final caption = TextStyle(fontSize: 12, color: tokens.secondaryForeground);
    final hasMatches = matchCount > 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.sidebar,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacingSm,
          vertical: tokens.spacingXs,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('code_viewer_search_field'),
                    controller: searchController,
                    enabled: onSearchChanged != null,
                    onChanged: onSearchChanged,
                    textInputAction: TextInputAction.search,
                    // Enter steps to the next hit and leaves the focus in the
                    // field, so pressing it again steps again.
                    onEditingComplete: () {},
                    onSubmitted: (_) => onNextMatch?.call(),
                    decoration: const InputDecoration(
                      hintText: 'Search',
                      prefixIcon: Icon(QuarkIcons.search),
                    ),
                  ),
                ),
                QuarkBarIconButton(
                  key: const ValueKey('code_viewer_search_previous'),
                  icon: QuarkIcons.expand_less,
                  tooltip: 'Previous result',
                  onPressed: hasMatches ? onPreviousMatch : null,
                ),
                QuarkBarIconButton(
                  key: const ValueKey('code_viewer_search_next'),
                  icon: QuarkIcons.expand_more,
                  tooltip: 'Next result',
                  onPressed: hasMatches ? onNextMatch : null,
                ),
                QuarkBarIconButton(
                  key: const ValueKey('code_viewer_wrap_toggle'),
                  icon: QuarkIcons.notes_rounded,
                  tooltip: 'Wrap lines',
                  selected: wrap,
                  onPressed: onWrapChanged == null
                      ? null
                      : () => onWrapChanged!(!wrap),
                ),
              ],
            ),
            if (counter.isNotEmpty || status != null)
              Padding(
                padding: EdgeInsets.only(
                  top: tokens.spacingXs,
                  left: tokens.spacingXs,
                  right: tokens.spacingXs,
                ),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: tokens.spacingMd,
                  children: [
                    if (counter.isNotEmpty)
                      Text(
                        counter,
                        key: const ValueKey('code_viewer_match_count'),
                        style: caption,
                      ),
                    if (status != null)
                      Text(
                        status,
                        key: const ValueKey('code_viewer_status'),
                        style: caption,
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
