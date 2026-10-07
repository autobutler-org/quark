import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/slide_present_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/widgets/slides/present/slide_present_body.dart';
import 'package:quark/widgets/slides/present/slide_present_shortcuts.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Presenting a `.qslide` full-window, at `/slides/<path>/present` with
/// `?slide=N` to start part way (#1165): the slide centered on a dark
/// background, stepped through by key, tap or swipe, with a control bar that
/// hides when idle, a presenter view with the next slide, the speaker notes
/// (#1166) and a clock on a wide screen, and fullscreen where the platform
/// has it.
///
/// It is always dark, whatever the app's theme, as a projector wants. Escape,
/// the bar's close button and a system back all end the show in the editor
/// at `/slides/<path>?slide=N`, on the slide the show ended on (#2900), out
/// of fullscreen.
class SlidePresentPage extends StatefulWidget {
  /// Presents the file at [filePath] on the device [deviceSerial], from the
  /// slide at [startIndex].
  const SlidePresentPage({
    required this.filePath,
    this.deviceSerial = '',
    this.startIndex = 0,
    this.initial,
    this.controller,
    super.key,
  });

  /// The presentation's path, relative to the device's files root.
  final String filePath;

  /// The device the file is on; empty for the Quark's own storage.
  final String deviceSerial;

  /// The slide to start at, counting from 0.
  final int startIndex;

  /// The editor's copy of the presentation, shown without loading the file;
  /// null on a link or a reload.
  final Presentation? initial;

  /// The page's state, for tests that pass fakes; built from the other
  /// fields when null.
  final SlidePresentController? controller;

  @override
  State<SlidePresentPage> createState() => _SlidePresentPageState();
}

class _SlidePresentPageState extends State<SlidePresentPage> {
  late final SlidePresentController _controller =
      widget.controller ??
      SlidePresentController(
        filePath: widget.filePath,
        deviceSerial: widget.deviceSerial,
        startIndex: widget.startIndex,
        initial: widget.initial,
      );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    unawaited(_controller.leaveFullscreen());
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _exit() async {
    await _controller.leaveFullscreen();
    if (!mounted) return;
    context.go(
      AppRoutes.slideFile(
        widget.filePath,
        serial: widget.deviceSerial,
        slide: _controller.index + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: QuarkTheme.dark(themeColor: AppSettings.instance.themeColor.value),
    child: PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exit();
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Scaffold(
          body: SafeArea(
            child: SlidePresentShortcuts(
              onNext: _controller.next,
              onPrevious: _controller.previous,
              onFirst: _controller.first,
              onLast: _controller.last,
              onExit: _exit,
              onToggleFullscreen: _controller.canToggleFullscreen
                  ? _controller.toggleFullscreen
                  : null,
              child: SlidePresentBody(controller: _controller, onExit: _exit),
            ),
          ),
        ),
      ),
    ),
  );
}
