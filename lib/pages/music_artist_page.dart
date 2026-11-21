import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/router.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/music/music_album_grid.dart';
import 'package:quark/widgets/music/music_load_state.dart';
import 'package:quark/widgets/music/music_track_list.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One album artist of the music library (#3283), at
/// `/music/artists/<name>`: their albums and their songs, one tab each.
///
/// Key prefixes: `music_back` on the bar's way back to Artists,
/// `music_album_<albumKey>` on each album and `music_track_<path>` on each
/// song.
class MusicArtistPage extends StatefulWidget {
  /// Creates the page for the album artist [name]. [controller] is for
  /// tests.
  const MusicArtistPage({required this.name, this.controller, super.key});

  /// The album artist to show.
  final String name;

  /// The page's state; the real services when null.
  final MusicController? controller;

  @override
  State<MusicArtistPage> createState() => _MusicArtistPageState();
}

class _MusicArtistPageState extends State<MusicArtistPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final MusicController _controller =
      widget.controller ?? MusicController(artist: widget.name);

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) EventsService.instance.start();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _play(MusicTrack track) => context.go(
    AppRoutes.viewFilePath(
      track.relPath,
      serial: track.serial,
      from: AppRoutes.musicArtist(widget.name),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: widget.name,
      icon: QuarkIcons.person_outline,
      onRefresh: manualRefresh,
      isRefreshing: isRefreshing,
      actions: [
        QuarkBarIconButton(
          key: const ValueKey('music_back'),
          icon: QuarkIcons.arrow_back,
          tooltip: 'Back to artists',
          onPressed: () => context.go(AppRoutes.musicTab(MusicTab.artists)),
        ),
      ],
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.music),
      body: RefreshIndicator(
        onRefresh: manualRefresh,
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => MusicLoadState(
            loading:
                isInitialLoad &&
                _controller.tracks.isEmpty &&
                _controller.albums.isEmpty,
            error: _controller.error,
            action: 'load the artist',
            onRetry: manualRefresh,
            child: QuarkTabView(
              tabs: [
                QuarkTab(
                  label: 'Albums',
                  child: MusicAlbumGrid(
                    albums: _controller.albums,
                    onTap: (key) => context.go(AppRoutes.musicAlbum(key)),
                  ),
                ),
                QuarkTab(
                  label: 'Songs',
                  child: MusicTrackList(
                    tracks: _controller.tracks,
                    onTap: _play,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
