import 'package:flutter/material.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/music/music_albums_grid.dart';
import 'package:quark/widgets/music/music_artists_list.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark/widgets/music/music_genre_filter.dart';
import 'package:quark/widgets/music/music_genres_list.dart';
import 'package:quark/widgets/music/music_history_sections.dart';
import 'package:quark/widgets/music/music_items.dart';
import 'package:quark/widgets/music/music_search_field.dart';
import 'package:quark/widgets/music/music_songs_list.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the Music app bar (#3283): the first load, the error
/// view, the scanning or empty library, and otherwise the search box over
/// either the search results or the Songs, Albums, Artists and Genres tabs.
/// Songs opens with the user's Recently played and Most played
/// ([MusicHistorySections]) unless it is narrowed to a genre.
///
/// A refresh that fails with a library already on screen keeps it and
/// names the failure above the tabs (`music_error`).
///
/// Keys: `music_error` on that line, and the keys of [MusicSearchField],
/// [MusicGenreFilter], [MusicHistorySections] and the package's music
/// widgets.
class MusicLibraryBody extends StatelessWidget {
  /// Shows [controller]'s library on [tab].
  const MusicLibraryBody({
    required this.controller,
    required this.tab,
    required this.onTabSelected,
    required this.onTrackTap,
    required this.onAlbumTap,
    required this.onArtistTap,
    required this.onGenreTap,
    required this.onClearGenre,
    required this.onRetry,
    this.onScan,
    super.key,
  });

  /// The library's state.
  final MusicController controller;

  /// The tab to show.
  final MusicTab tab;

  /// Called with the tab the user picked.
  final ValueChanged<MusicTab>? onTabSelected;

  /// Called with the song tapped, in a tab or the search results.
  final ValueChanged<MusicTrackItem> onTrackTap;

  /// Called with the album key tapped.
  final ValueChanged<String> onAlbumTap;

  /// Called with the artist name tapped.
  final ValueChanged<String> onArtistTap;

  /// Called with the genre tapped.
  final ValueChanged<String> onGenreTap;

  /// Shows every song again after a genre.
  final VoidCallback onClearGenre;

  /// Fetches the library again from the error view.
  final VoidCallback onRetry;

  /// Queues a scan from the empty library; null hides the button, as for
  /// anyone but an admin.
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final error = c.error;
    if (!c.isLoaded) {
      return error == null
          ? const Center(child: QuarkLoader())
          : SlidesErrorView(
              error: error,
              action: c.errorAction,
              onRetry: onRetry,
            );
    }
    if (c.isEmpty) {
      return MusicLibraryEmptyState(isScanning: c.isScanning, onScan: onScan);
    }
    final genre = c.genre;
    final searchError = c.searchError;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MusicSearchField(onChanged: c.setQuery),
        if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              Errors.message(error, c.errorAction),
              key: const ValueKey('music_error'),
              style: TextStyle(color: QuarkTokens.of(context).error),
            ),
          ),
        Expanded(
          child: c.query.isNotEmpty
              ? SingleChildScrollView(
                  child: MusicSearchResults(
                    query: c.query,
                    results: [for (final hit in c.results) hit.toResult()],
                    isLoading: c.isSearching,
                    error: searchError == null
                        ? null
                        : Errors.message(searchError, 'search your music'),
                    coverBuilder: (context, result) => MusicCover(
                      path: result.track.path,
                      serial: result.track.serial,
                    ),
                    onTrackTap: onTrackTap,
                  ),
                )
              : QuarkTabView(
                  selectedIndex: tab.index,
                  onTabSelected: onTabSelected == null
                      ? null
                      : (i) => onTabSelected!(MusicTab.values[i]),
                  tabs: [
                    QuarkTab(
                      label: 'Songs',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (genre != null)
                            MusicGenreFilter(
                              genre: genre,
                              onClear: onClearGenre,
                            ),
                          Expanded(
                            child: MusicSongsList(
                              header: [
                                if (genre == null &&
                                    (c.recent.isNotEmpty ||
                                        c.mostPlayed.isNotEmpty))
                                  MusicHistorySections(
                                    recent: c.recent,
                                    mostPlayed: c.mostPlayed,
                                    onTrackTap: onTrackTap,
                                  ),
                              ],
                              tracks: c.tracks,
                              hasMore: c.hasMoreTracks,
                              isLoadingMore: c.isLoadingMore,
                              onLoadMore: c.loadMoreTracks,
                              onTrackTap: onTrackTap,
                              emptyText: 'No songs in this genre.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    QuarkTab(
                      label: 'Albums',
                      child: MusicAlbumsGrid(
                        albums: c.albums,
                        hasMore: c.hasMoreAlbums,
                        isLoadingMore: c.isLoadingMore,
                        onLoadMore: c.loadMoreAlbums,
                        onAlbumTap: onAlbumTap,
                      ),
                    ),
                    QuarkTab(
                      label: 'Artists',
                      child: MusicArtistsList(
                        artists: c.artists,
                        hasMore: c.hasMoreArtists,
                        isLoadingMore: c.isLoadingMore,
                        onLoadMore: c.loadMoreArtists,
                        onArtistTap: onArtistTap,
                      ),
                    ),
                    QuarkTab(
                      label: 'Genres',
                      child: MusicGenresList(
                        genres: c.genres,
                        onGenreTap: onGenreTap,
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}
