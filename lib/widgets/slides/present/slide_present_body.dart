import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_present_controller.dart';
import 'package:quark/widgets/slides/present/slide_present_controls.dart';
import 'package:quark/widgets/slides/present/slide_present_stage.dart';
import 'package:quark/widgets/slides/present/slide_presenter_view.dart';
import 'package:quark/widgets/slides/slide_image.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything on screen while presenting (#1165): the loader, the load
/// error, or the slide ([SlidePresentStage]) with the control bar
/// ([SlidePresentControls]) over its foot.
///
/// With the presenter view on, a wide window shows the [SlidePresenterView]
/// with the bar docked under it and always showing, since that screen is the
/// speaker's. A phone — narrower than [QuarkSplitView.collapseBreakpoint] —
/// has no room for it and shows the slide alone, without the toggle.
///
/// Moving a mouse, or touching the screen, brings the bar back; a click
/// steps through the slides without waking it, so a presenter clicking
/// through is not left with the bar over every slide.
///
/// Pictures are [SlideImage]s fetched through the Quark's authenticated
/// download URL ([SlidePresentController.imageUrl]).
///
/// It reads [controller] and calls its commands; the page owns the
/// controller and decides what [onExit] does.
///
/// Key prefixes: `slide_present_stage` on the slide, and the controls'.
class SlidePresentBody extends StatelessWidget {
  /// Shows [controller]'s presentation.
  const SlidePresentBody({
    required this.controller,
    required this.onExit,
    super.key,
  });

  /// The running presentation.
  final SlidePresentController controller;

  /// Ends the show.
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final presentation = c.presentation;
    final slide = c.currentSlide;
    if (c.isLoading) return const Center(child: QuarkLoader());
    if (presentation == null || slide == null) {
      return SlidesErrorView(
        error: c.loadError ?? StateError('no slides'),
        action: 'open the presentation',
        onRetry: c.load,
      );
    }

    final collapsed = QuarkSplitView.isCollapsed(context);
    final speaker = c.presenterView && !collapsed;
    Widget imageBuilder(BuildContext context, SlideImageSource image) =>
        SlideImage(
          image: NetworkImage(c.imageUrl(image.source).toString()),
          fit: image.fit,
        );
    final stage = SlidePresentStage(
      key: const ValueKey('slide_present_stage'),
      slide: slide,
      size: presentation.size,
      label: c.position,
      onNext: c.isLast ? null : c.next,
      onPrevious: c.isFirst ? null : c.previous,
      imageBuilder: imageBuilder,
      theme: presentation.theme,
    );
    final controls = SlidePresentControls(
      visible: speaker || c.controlsVisible,
      position: c.position,
      onPrevious: c.isFirst ? null : c.previous,
      onNext: c.isLast ? null : c.next,
      onExit: onExit,
      presenterView: c.presenterView,
      onTogglePresenterView: collapsed ? null : c.togglePresenterView,
      isFullscreen: c.isFullscreen,
      onToggleFullscreen: c.canToggleFullscreen ? c.toggleFullscreen : null,
    );

    return MouseRegion(
      onHover: (_) => c.wakeControls(),
      child: Listener(
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.touch) c.wakeControls();
        },
        child: speaker
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SlidePresenterView(
                      stage: stage,
                      next: c.nextSlide,
                      size: presentation.size,
                      notes: slide.notes,
                      elapsed: c.elapsed,
                      imageBuilder: imageBuilder,
                      theme: presentation.theme,
                    ),
                  ),
                  Center(child: controls),
                ],
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  stage,
                  Align(alignment: Alignment.bottomCenter, child: controls),
                ],
              ),
      ),
    );
  }
}
