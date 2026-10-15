import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/empty_state_widget.dart';
import '../core/quark_loader.dart';
import '../theme/quark_tokens.dart';
import 'music_search_result.dart';
import 'music_track_item.dart';
import 'track_list_tile.dart';

/// Music search results with explicit loading, error, prompt, and empty states.
///
/// Results render as [TrackListTile] rows. The caller supplies any cover image
/// through [coverBuilder] and receives the selected [MusicTrackItem] through
/// [onTrackTap]. Error copy is rendered exactly as supplied in [error].
///
/// Key prefix: `music_track_<path>` on every result row.
///
/// ```dart
/// MusicSearchResults(
///   query: controller.query,
///   results: controller.results,
///   isLoading: controller.isSearching,
///   error: controller.error,
///   onTrackTap: openTrack,
/// );
/// ```
class MusicSearchResults extends StatelessWidget {
  /// Creates the results for [query].
  const MusicSearchResults({
    required this.results,
    this.query = '',
    this.isLoading = false,
    this.error,
    this.coverBuilder,
    this.onTrackTap,
    super.key,
  });

  /// The query these [results] answer. Empty shows the initial search prompt.
  final String query;

  /// The matching tracks and excerpts, in API ranking order.
  final List<MusicSearchResult> results;

  /// Whether a search is in progress. Replaces every other state.
  final bool isLoading;

  /// A caller-composed failure sentence. Replaces results when non-null.
  final String? error;

  /// Builds cover art for a result. Null shows the placeholder.
  final Widget Function(BuildContext context, MusicSearchResult result)?
  coverBuilder;

  /// Called with the track whose result row was tapped.
  final ValueChanged<MusicTrackItem>? onTrackTap;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = this.error;

    if (isLoading) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingLg),
        child: const Center(child: QuarkLoader()),
      );
    }
    if (error != null) {
      return Padding(
        padding: EdgeInsets.all(tokens.spacingMd),
        child: Text(
          error,
          textAlign: TextAlign.center,
          style: TextStyle(color: tokens.error),
        ),
      );
    }
    if (results.isEmpty) {
      return EmptyStateWidget(
        icon: QuarkIcons.search,
        headline: query.isEmpty ? 'Search your music' : 'No matches',
        subtext: query.isEmpty
            ? 'Find a title, artist, album, or genre.'
            : 'Nothing matched “$query”.',
      );
    }

    final coverBuilder = this.coverBuilder;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final result in results) ...[
          TrackListTile(
            item: result.track,
            coverBuilder: coverBuilder == null
                ? null
                : (context) => coverBuilder(context, result),
            onTap: onTrackTap,
          ),
          Padding(
            padding: EdgeInsets.only(
              left: tokens.spacingMd + 48 + tokens.spacingMd,
              right: tokens.spacingMd,
              bottom: tokens.spacingSm,
            ),
            child: Text(
              result.snippet,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tokens.mutedForeground),
            ),
          ),
        ],
      ],
    );
  }
}
