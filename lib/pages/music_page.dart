import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/music_controller.dart';
import 'package:quark/models/music_track.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/events_service.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/app_drawer.dart';
import 'package:quark/widgets/music/music_library_body.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The Music page (#3283): the Quark's music library in four tabs, Songs,
/// Albums, Artists and Genres, each with its own URL, and a search over
/// every tag. A song opens in the audio player; an album or an artist opens
/// its own page. Tapping a genre filters Songs to it.
///
/// It fetches again when the Quark says the library changed.
class MusicPage extends StatefulWidget {
  /// Creates the page on [tab]. [controller] is for tests, which pass one
  /// with fake services.
  const MusicPage({
    this.tab = MusicTab.songs,
    this.onTabSelected,
    this.controller,
    super.key,
  });

  /// The tab to show.
  final MusicTab tab;

  /// Called with the tab the user picked. Null keeps the choice in the view.
  final ValueChanged<MusicTab>? onTabSelected;

  /// The page's state; the real services when null.
  final MusicController? controller;

  @override
  State<MusicPage> createState() => _MusicPageState();
}

class _MusicPageState extends State<MusicPage>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final MusicController _controller =
      widget.controller ?? MusicController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) EventsService.instance.start();
    // The field also notifies on a cursor move; only new text searches.
    _search.addListener(() {
      if (_search.text.trim() != _controller.query) {
        _controller.search(_search.text);
      }
    });
  }

  @override
  void dispose() {
    _search.dispose();
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Future<void> refresh() => _controller.refresh();

  void _selectTab(MusicTab tab) => widget.onTabSelected?.call(tab);

  void _play(MusicTrack track) => context.go(
    AppRoutes.viewFilePath(
      track.relPath,
      serial: track.serial,
      from: AppRoutes.musicTab(widget.tab),
    ),
  );

  void _filterGenre(String genre) {
    _controller.filterGenre(genre);
    _selectTab(MusicTab.songs);
  }

  Future<void> _scan() async {
    final error = await _controller.rescan();
    if (error == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(Errors.message(error, 'scan your music'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return QuarkPageScaffold(
      title: 'Music',
      icon: QuarkIcons.music_note,
      onRefresh: manualRefresh,
      isRefreshing: isRefreshing,
      drawer: const AppDrawer(activeSection: QuarkDrawerSection.music),
      // A phone's bar has no refresh button, so the lists pull to refresh
      // (#4150). They sit in a tab view, one scrollable deeper than the
      // indicator listens by default.
      body: RefreshIndicator(
        onRefresh: manualRefresh,
        notificationPredicate: (n) => n.metrics.axis == Axis.vertical,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => MusicLibraryBody(
            controller: _controller,
            loading: isInitialLoad && _controller.status == null,
            tab: widget.tab,
            searchController: _search,
            onTabSelected: _selectTab,
            onRetry: manualRefresh,
            onTrackTap: _play,
            onAlbumTap: (key) => context.go(AppRoutes.musicAlbum(key)),
            onArtistTap: (name) => context.go(AppRoutes.musicArtist(name)),
            onGenreTap: _filterGenre,
            onClearGenre: () => _controller.filterGenre(null),
            onScan: AppSettings.instance.isAdmin.value ? _scan : null,
          ),
        ),
      ),
    );
  }
}
