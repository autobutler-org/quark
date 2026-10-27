import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/music_album_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/music/music_album_header.dart';
import 'package:quark/widgets/music/music_cover.dart';
import 'package:quark/widgets/music/music_detail_body.dart';
import 'package:quark/widgets/music/music_songs_list.dart';

/// One album's page, `/music/albums/<albumKey>` (#3283): its cover, title,
/// artist and year over its tracks in album order. A track opens in the
/// audio player and closes back here; the back button goes to Albums.
class MusicAlbumPage extends StatefulWidget {
  /// Creates the page for [albumKey]. [controller] is for tests.
  const MusicAlbumPage({required this.albumKey, this.controller, super.key});

  /// The album to show.
  final String albumKey;

  /// The page's state; the real service when null.
  final MusicAlbumController? controller;

  @override
  State<MusicAlbumPage> createState() => _MusicAlbumPageState();
}

class _MusicAlbumPageState extends State<MusicAlbumPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final MusicAlbumController _controller =
      widget.controller ?? MusicAlbumController(albumKey: widget.albumKey);

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
      : context.go(AppRoutes.musicTab(MusicTab.albums));

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final cover = _controller.coverTrack;
        final title = _controller.title.isEmpty
            ? 'Unknown album'
            : _controller.title;
        return Scaffold(
          key: const ValueKey('music_album_page'),
          appBar: ChromeAppBar(
            leading: BackButton(onPressed: _back),
            title: Text(_controller.isLoaded ? title : 'Album'),
          ),
          body: MusicDetailBody(
            isLoaded: _controller.isLoaded,
            error: _controller.error,
            action: 'load the album',
            onRetry: manualRefresh,
            child: MusicSongsList(
              header: [
                MusicAlbumHeader(
                  title: title,
                  albumArtist: _controller.albumArtist,
                  year: _controller.year,
                  trackCount: _controller.tracks.length,
                  coverBuilder: cover == null
                      ? null
                      : MusicCover.builder(cover.relPath, serial: cover.serial),
                ),
              ],
              tracks: _controller.tracks,
              emptyText: 'Nothing on this album is yours to play.',
              onTrackTap: (track) => context.go(
                AppRoutes.viewFilePath(
                  track.path,
                  serial: track.serial,
                  from: AppRoutes.musicAlbum(widget.albumKey),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
