import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The bar over a running presentation (#1165): previous, where the show is
/// ("Slide 2 of 5"), next, the presenter view toggle, fullscreen, and end.
///
/// It fades out while [visible] is false — the pointer has rested a while —
/// and takes no taps then. Under reduced motion it disappears without the
/// fade. A screen reader has no pointer to wake it with, so with one
/// running it never hides.
///
/// The buttons wrap onto a second row rather than overflow a phone at a
/// large text size.
///
/// Key prefixes: `slide_present_controls` on the fading bar,
/// `slide_present_previous`, `slide_present_next`,
/// `slide_present_presenter_view`, `slide_present_fullscreen` and
/// `slide_present_exit` on its buttons.
///
/// ```dart
/// SlidePresentControls(
///   visible: c.controlsVisible,
///   position: c.position,
///   onPrevious: c.isFirst ? null : c.previous,
///   onNext: c.isLast ? null : c.next,
///   onExit: exit,
/// );
/// ```
class SlidePresentControls extends StatelessWidget {
  /// Creates the bar reading [position].
  const SlidePresentControls({
    required this.visible,
    required this.position,
    required this.onPrevious,
    required this.onNext,
    required this.onExit,
    this.presenterView = false,
    this.onTogglePresenterView,
    this.isFullscreen = false,
    this.onToggleFullscreen,
    super.key,
  });

  /// Whether the bar is showing.
  final bool visible;

  /// Where the show is, such as "Slide 2 of 5".
  final String position;

  /// Shows the previous slide; null at the first.
  final VoidCallback? onPrevious;

  /// Shows the next slide; null at the last.
  final VoidCallback? onNext;

  /// Ends the show.
  final VoidCallback onExit;

  /// Whether the presenter view is on; tints its toggle.
  final bool presenterView;

  /// Turns the presenter view on or off; null hides the toggle, on a screen
  /// too narrow for it.
  final VoidCallback? onTogglePresenterView;

  /// Whether the app is fullscreen.
  final bool isFullscreen;

  /// Enters or leaves fullscreen; null hides the button where the platform
  /// has no fullscreen.
  final VoidCallback? onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final shown = visible || MediaQuery.accessibleNavigationOf(context);
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) ||
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .reduceMotion;
    final onTogglePresenterView = this.onTogglePresenterView;
    final onToggleFullscreen = this.onToggleFullscreen;
    return AnimatedOpacity(
      key: const ValueKey('slide_present_controls'),
      opacity: shown ? 1 : 0,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      child: IgnorePointer(
        ignoring: !shown,
        child: ExcludeSemantics(
          excluding: !shown,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingSm),
            child: Material(
              color: tokens.card,
              borderRadius: BorderRadius.circular(tokens.radiusLg),
              child: Padding(
                padding: EdgeInsets.all(tokens.spacingXs),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    QuarkBarIconButton(
                      key: const ValueKey('slide_present_previous'),
                      icon: QuarkIcons.chevron_left,
                      tooltip: 'Previous slide',
                      onPressed: onPrevious,
                    ),
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: tokens.spacingSm,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          position,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(color: tokens.foreground),
                        ),
                      ),
                    ),
                    QuarkBarIconButton(
                      key: const ValueKey('slide_present_next'),
                      icon: QuarkIcons.chevron_right,
                      tooltip: 'Next slide',
                      onPressed: onNext,
                    ),
                    if (onTogglePresenterView != null)
                      QuarkBarChip(
                        key: const ValueKey('slide_present_presenter_view'),
                        icon: QuarkIcons.notes_rounded,
                        label: 'Presenter view',
                        tooltip: presenterView
                            ? 'Hide the presenter view'
                            : 'Show the next slide, notes and time',
                        active: presenterView,
                        onPressed: onTogglePresenterView,
                      ),
                    if (onToggleFullscreen != null)
                      QuarkBarIconButton(
                        key: const ValueKey('slide_present_fullscreen'),
                        icon: isFullscreen
                            ? QuarkIcons.fullscreen_exit
                            : QuarkIcons.fullscreen,
                        tooltip: isFullscreen
                            ? 'Exit fullscreen'
                            : 'Fullscreen',
                        onPressed: onToggleFullscreen,
                      ),
                    QuarkBarIconButton(
                      key: const ValueKey('slide_present_exit'),
                      icon: QuarkIcons.close,
                      tooltip: 'End the presentation',
                      onPressed: onExit,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
