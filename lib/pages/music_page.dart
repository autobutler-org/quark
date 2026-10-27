import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/music/music_library_body.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Music page (#3283): the library built from the audio files on the
/// Quark, as Songs, Albums, Artists and Genres tabs with a tag search over
/// them. Each tab has its own URL (`/music/<tab>`), and Songs narrowed to a
/// genre is `/music/songs?genre=<name>`.
///
/// A song opens in the file viewer's audio player and closes back here; an
/// album or artist opens its own page. An admin looking at an empty library
/// can start a scan from it.
class MusicPage extends StatefulWidget {
  /// Creates the page on [tab]. [controller] is for tests, which pass one
  /// with fake services.
  const MusicPage({
    this.tab = MusicTab.songs,
    this.onTabSelected,
    this.genre,
    this.controller,
    super.key,
  });

  /// The tab to show.
  final MusicTab tab;

  /// Moves to another tab's URL; from [tabbedRoutes].
  final ValueChanged<MusicTab>? onTabSelected;

  /// The genre Songs is narrowed to, '' for untagged, null for every song.
  final String? genre;

  /// The page's state; the real services when null.
  final MusicController? controller;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final MusicController _controller =
      widget.controller ?? MusicController();
  bool _started = false;

  @override
  void didUpdateWidget(MusicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.genre != oldWidget.genre) _controller.setGenre(widget.genre);
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() {
    if (_started) return _controller.refresh();
    _started = true;
    _controller.setGenre(widget.genre);
    return _controller.start();
  }

  String get _here => GoRouterState.of(context).uri.toString();

  void _openTrack(MusicTrackItem track) => context.go(
    AppRoutes.viewFilePath(track.path, serial: track.serial, from: _here),
  );

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: 'Music',
      icon: QuarkIcons.library_music_outlined,
      onRefresh: manualRefresh,
      isRefreshing: isRefreshing,
      actions: const [AppThemeToggle()],
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.music),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          _controller,
          AppSettings.instance.isAdmin,
        ]),
        builder: (context, _) => MusicLibraryBody(
          controller: _controller,
          tab: widget.tab,
          onTabSelected: widget.onTabSelected,
          onTrackTap: _openTrack,
          onAlbumTap: (key) => context.go(AppRoutes.musicAlbum(key)),
          onArtistTap: (name) => context.go(AppRoutes.musicArtist(name)),
          onGenreTap: (genre) => context.go(AppRoutes.musicGenre(genre)),
          onClearGenre: () => context.go(AppRoutes.musicTab(MusicTab.songs)),
          onRetry: manualRefresh,
          onScan: AppSettings.instance.isAdmin.value
              ? _controller.rescan
              : null,
        ),
      ),
    );
  }
}
