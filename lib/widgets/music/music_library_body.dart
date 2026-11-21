import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/file_type_search_bar.dart';
import 'package:quark/widgets/music/music_album_grid.dart';
import 'package:quark/widgets/music/music_artist_list.dart';
import 'package:quark/widgets/music/music_genre_filter.dart';
import 'package:quark/widgets/music/music_genre_list.dart';
import 'package:quark/widgets/music/music_load_state.dart';
import 'package:quark/widgets/music/music_track_list.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the Music app bar (#3283): the search field, then either
/// the search results, or the library in four tabs — Songs, Albums, Artists
/// and Genres. A library with no tracks shows [MusicLibraryEmptyState]
/// instead, "scanning" while the Quark's scan is under way.
///
/// It reads [controller] and changes nothing: every action calls back.
///
/// Key prefixes: `music_search` and `music_search_clear` on the field, from
/// [FileTypeSearchBar]; the package widgets' `music_track_<path>`,
/// `music_album_<albumKey>`, `music_artist_<name>` and `music_genre_<name>`;
/// [MusicGenreFilter]'s `music_genre_filter`; and `music_scan` on the empty
/// state's scan button.
class MusicLibraryBody extends StatelessWidget {
  /// Shows [controller]'s library on [tab].
  const MusicLibraryBody({
    required this.controller,
    required this.loading,
    required this.tab,
    required this.searchController,
    required this.onTabSelected,
    required this.onRetry,
    required this.onTrackTap,
    required this.onAlbumTap,
    required this.onArtistTap,
    required this.onGenreTap,
    required this.onClearGenre,
    this.onScan,
    super.key,
  });

  /// The library's state.
  final MusicController controller;

  /// Whether the first listing is still on its way, with nothing to show.
  final bool loading;

  /// The tab to show.
  final MusicTab tab;

  /// The search text, owned by the page.
  final TextEditingController searchController;

  /// Called with the tab picked.
  final ValueChanged<MusicTab> onTabSelected;

  /// Called by the error view's retry button.
  final VoidCallback onRetry;

  /// Called with the song tapped, in a tab or the search results.
  final ValueChanged<MusicTrack> onTrackTap;

  /// Called with the key of the album tapped.
  final ValueChanged<String> onAlbumTap;

  /// Called with the name of the artist tapped.
  final ValueChanged<String> onArtistTap;

  /// Called with the name of the genre tapped.
  final ValueChanged<String> onGenreTap;

  /// Called when the genre filter on Songs is cleared.
  final VoidCallback onClearGenre;

  /// Queues a scan from the empty state. Null, for anyone but an admin,
  /// hides the button.
  final VoidCallback? onScan;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final status = c.status;
    final genre = c.genre;
    final tracksByPath = {for (final t in c.results) t.track.relPath: t.track};
    return Column(
      children: [
        FileTypeSearchBar(
          controller: searchController,
          hintText: 'Search music…',
          keyPrefix: 'music',
        ),
        Expanded(
          child: c.query.isNotEmpty
              ? SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: MusicSearchResults(
                    query: c.query,
                    isLoading: c.isSearching,
                    error: c.searchError == null
                        ? null
                        : Errors.message(c.searchError, 'search your music'),
                    results: [
                      for (final hit in c.results)
                        MusicSearchResult(
                          track: musicTrackItem(hit.track),
                          // The Quark marks the matched terms in <b>; this
                          // draws plain text.
                          snippet: hit.snippet.replaceAll(RegExp(r'</?b>'), ''),
                        ),
                    ],
                    onTrackTap: (item) {
                      final track = tracksByPath[item.path];
                      if (track != null) onTrackTap(track);
                    },
                  ),
                )
              : MusicLoadState(
                  loading: loading,
                  error: c.error,
                  action: 'load your music',
                  onRetry: onRetry,
                  child: status != null && status.trackCount == 0
                      ? CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: MusicLibraryEmptyState(
                                isScanning: status.isScanning,
                                onScan: onScan,
                              ),
                            ),
                          ],
                        )
                      : QuarkTabView(
                          selectedIndex: tab.index,
                          onTabSelected: (i) =>
                              onTabSelected(MusicTab.values[i]),
                          tabs: [
                            QuarkTab(
                              label: 'Songs',
                              child: MusicTrackList(
                                tracks: c.tracks,
                                onTap: onTrackTap,
                                header: genre == null
                                    ? null
                                    : MusicGenreFilter(
                                        genre: genre,
                                        onClear: onClearGenre,
                                      ),
                              ),
                            ),
                            QuarkTab(
                              label: 'Albums',
                              child: MusicAlbumGrid(
                                albums: c.albums,
                                onTap: onAlbumTap,
                              ),
                            ),
                            QuarkTab(
                              label: 'Artists',
                              child: MusicArtistList(
                                artists: c.artists,
                                onTap: onArtistTap,
                              ),
                            ),
                            QuarkTab(
                              label: 'Genres',
                              child: MusicGenreList(
                                genres: c.genres,
                                onTap: onGenreTap,
                              ),
                            ),
                          ],
                        ),
                ),
        ),
      ],
    );
  }
}
