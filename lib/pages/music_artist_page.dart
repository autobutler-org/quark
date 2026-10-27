import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/music_artist_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/music/music_artist_albums.dart';
import 'package:quark/widgets/music/music_detail_body.dart';
import 'package:quark/widgets/music/music_songs_list.dart';

/// One album artist's page, `/music/artist?name=<name>` (#3283): their
/// albums, then their songs by album. An album opens its page and a song
/// the audio player; the back button goes to Artists.
class MusicArtistPage extends StatefulWidget {
  /// Creates the page for [name], '' for the untagged artist. [controller]
  /// is for tests.
  const MusicArtistPage({required this.name, this.controller, super.key});

  /// The album artist to show.
  final String name;

  /// The page's state; the real service when null.
  final MusicArtistController? controller;

  @override
  State<MusicArtistPage> createState() => _MusicArtistPageState();
}

class _MusicArtistPageState extends State<MusicArtistPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final MusicArtistController _controller =
      widget.controller ?? MusicArtistController(name: widget.name);

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() =>
      isInitialLoad ? _controller.start() : _controller.refresh();

  void _back() => context.canPop()
      ? context.pop()
      : context.go(AppRoutes.musicTab(MusicTab.artists));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return Scaffold(
          key: const ValueKey('music_artist_page'),
          appBar: ChromeAppBar(
            leading: BackButton(onPressed: _back),
            title: Text(widget.name.isEmpty ? 'Unknown artist' : widget.name),
          ),
          body: MusicDetailBody(
            isLoaded: _controller.isLoaded,
            error: _controller.error,
            action: 'load the artist',
            onRetry: manualRefresh,
            child: MusicSongsList(
              header: [
                MusicArtistAlbums(
                  albums: _controller.albums,
                  onAlbumTap: (key) => context.go(AppRoutes.musicAlbum(key)),
                ),
              ],
              tracks: _controller.tracks,
              hasMore: _controller.hasMoreTracks,
              isLoadingMore: _controller.isLoadingMore,
              onLoadMore: _controller.loadMoreTracks,
              emptyText: 'Nothing by this artist is yours to play.',
              onTrackTap: (track) => context.go(
                AppRoutes.viewFilePath(
                  track.path,
                  serial: track.serial,
                  from: AppRoutes.musicArtist(widget.name),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
