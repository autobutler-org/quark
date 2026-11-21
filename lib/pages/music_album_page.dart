import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/router.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/music/music_load_state.dart';
import 'package:quark/widgets/music/music_track_list.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// One album of the music library (#3283), at `/music/albums/<albumKey>`:
/// its songs in album order, each opening in the audio player.
///
/// Key prefixes: `music_back` on the bar's way back to Albums, and
/// `music_track_<path>` on each song.
class MusicAlbumPage extends StatefulWidget {
  /// Creates the page for the album [albumKey]. [controller] is for tests.
  const MusicAlbumPage({required this.albumKey, this.controller, super.key});

  /// The album to show.
  final String albumKey;

  /// The page's state; the real services when null.
  final MusicController? controller;

  @override
  State<MusicAlbumPage> createState() => _MusicAlbumPageState();
}

class _MusicAlbumPageState extends State<MusicAlbumPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final MusicController _controller =
      widget.controller ?? MusicController(albumKey: widget.albumKey);

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
      from: AppRoutes.musicAlbum(widget.albumKey),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => QuarkPageScaffold(
        title: _controller.tracks.firstOrNull?.album ?? 'Album',
        icon: QuarkIcons.disc_full,
        onRefresh: manualRefresh,
        isRefreshing: isRefreshing,
        actions: [
          QuarkBarIconButton(
            key: const ValueKey('music_back'),
            icon: QuarkIcons.arrow_back,
            tooltip: 'Back to albums',
            onPressed: () => context.go(AppRoutes.musicTab(MusicTab.albums)),
          ),
        ],
        drawer: const AppDrawer(activeSection: QuarkDrawerSection.music),
        body: RefreshIndicator(
          onRefresh: manualRefresh,
          child: MusicLoadState(
            loading: isInitialLoad && _controller.tracks.isEmpty,
            error: _controller.error,
            action: 'load the album',
            onRetry: manualRefresh,
            child: MusicTrackList(tracks: _controller.tracks, onTap: _play),
          ),
        ),
      ),
    );
  }
}
