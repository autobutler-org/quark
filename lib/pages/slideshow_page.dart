import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/slideshow_controller.dart';
import 'package:quark/models/slideshow_photo.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/overlay_history.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Plays photos full screen in the app (#4179): an album, a selection,
/// search results, or a category, from any of which it was opened.
///
/// Arrow keys step, space pauses, and Escape or Exit closes it, back to
/// where it was opened. The screen stays on while it plays.
///
/// Open it with [SlideshowPage.open], which skips nothing itself: the
/// controller leaves out the videos.
class SlideshowPage extends StatefulWidget {
  const SlideshowPage({
    super.key,
    required this.controller,
    this.keepScreenOn = _keepScreenOn,
  });

  /// The slideshow, which the page starts and disposes.
  final SlideshowController controller;

  /// Turns the screen's stay-awake on or off.
  final void Function(bool on) keepScreenOn;

  /// Pushes a slideshow of [photos], starting at [startIndex], over the page
  /// at [context], and returns when it is closed. [loadSlide] reads one
  /// photo; the default reads Quark photos only.
  static Future<void> open(
    BuildContext context, {
    required List<SlideshowPhoto> photos,
    int startIndex = 0,
    LoadSlide loadSlide = loadQuarkSlide,
  }) => pushWithBrowserBack<void>(
    context,
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SlideshowPage(
        controller: SlideshowController(
          photos: photos,
          startIndex: startIndex,
          loadSlide: loadSlide,
        ),
      ),
    ),
  );

  @override
  State<SlideshowPage> createState() => _SlideshowPageState();
}

class _SlideshowPageState extends State<SlideshowPage> {
  SlideshowController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    widget.keepScreenOn(true);
    _controller.start();
  }

  @override
  void dispose() {
    widget.keepScreenOn(false);
    _controller.dispose();
    super.dispose();
  }

  void _exit() => Navigator.of(context).maybePop();

  Future<void> _pickMusic() async {
    final picked = await showModalBottomSheet<({String? id})>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => SlideshowMusicPicker(
            options: [
              for (final album in _controller.musicAlbums)
                SlideshowMusicOption(
                  id: album.key,
                  title: album.title,
                  subtitle: album.albumArtist,
                ),
            ],
            selectedId: _controller.musicAlbum?.key,
            isLoading: _controller.musicLoading,
            error: _controller.musicError == null
                ? null
                : Errors.message(_controller.musicError, 'load your music'),
            onSelected: (id) => Navigator.of(sheetContext).pop((id: id)),
          ),
        ),
      ),
    );
    if (picked == null) return;
    try {
      await _controller.chooseMusic(picked.id);
    } catch (e) {
      if (mounted) showMessage(context, Errors.message(e, 'play the music'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowRight): _controller.next,
        const SingleActivator(LogicalKeyboardKey.arrowLeft):
            _controller.previous,
        const SingleActivator(LogicalKeyboardKey.space):
            _controller.togglePlaying,
        const SingleActivator(LogicalKeyboardKey.escape): _exit,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: ListenableBuilder(
            listenable: _controller,
            builder: (context, _) {
              final c = _controller;
              final image = c.image;
              return SlideshowView(
                image: image == null ? null : MemoryImage(image),
                slideId: c.shown?.id,
                isLoading: c.isLoading,
                error: c.error == null
                    ? null
                    : Errors.message(c.error, 'load the photo'),
                isPlaying: c.isPlaying,
                intervalSeconds: c.intervalSeconds,
                intervalChoices: SlideshowController.intervalChoices,
                shuffle: c.shuffle,
                position: c.position,
                count: c.count,
                controlsVisible: c.controlsVisible,
                musicTitle: c.musicAlbum?.title,
                onActivity: c.showControls,
                onPlayPause: c.togglePlaying,
                onPrevious: c.previous,
                onNext: c.next,
                onIntervalChanged: c.setInterval,
                onShuffleChanged: c.setShuffle,
                onMusic: c.hasMusic ? _pickMusic : null,
                onExit: _exit,
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Keeps a phone's screen on, where the platform can; a platform without
/// the plugin just lets the screen sleep.
void _keepScreenOn(bool on) {
  unawaited(
    WakelockPlus.toggle(enable: on).catchError((Object e) {
      debugPrint('[slideshow_page.dart] wakelock error: $e');
    }),
  );
}
