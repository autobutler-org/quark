import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/notes/slide_notes_view.dart';
import 'package:quark/widgets/slides/present/slide_presenter_clock.dart';
import 'package:quark/widgets/slides/slide_editor_canvas.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The speaker's view of a running presentation on a wide screen (#1165):
/// the slide on screen ([stage]) on the left, and beside it the next slide,
/// the time since the show started, and the current slide's speaker notes
/// (#1166), read-only.
///
/// The next-slide preview shrinks before the notes do, so the notes keep
/// room at a large text size. After the last slide the preview reads "End of
/// presentation".
///
/// Key prefixes: `slide_presenter_next` on the preview, and
/// [SlidePresenterClock]'s and [SlideNotesView]'s inside it.
///
/// ```dart
/// SlidePresenterView(
///   stage: stage,
///   next: c.nextSlide,
///   size: presentation.size,
///   notes: c.currentSlide!.notes,
///   elapsed: c.elapsed,
/// );
/// ```
class SlidePresenterView extends StatelessWidget {
  /// Lays [stage] out beside what comes next and [notes].
  const SlidePresenterView({
    required this.stage,
    required this.next,
    required this.size,
    required this.notes,
    required this.elapsed,
    this.imageBuilder,
    this.theme,
    super.key,
  });

  /// The presentation's theme, which the slide is drawn in; null for none.
  final SlideTheme? theme;

  /// The slide on screen, as the audience sees it.
  final Widget stage;

  /// The slide after it, or null at the last.
  final Slide? next;

  /// The presentation's slide size.
  final SlideSize size;

  /// The current slide's speaker notes.
  final String notes;

  /// Time since the presentation started.
  final ValueListenable<Duration> elapsed;

  /// Draws image elements and background images in the preview.
  final SlideImageBuilder? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final heading = Theme.of(
      context,
    ).textTheme.titleSmall?.copyWith(color: tokens.mutedForeground);
    final next = this.next;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: stage),
        VerticalDivider(width: 1, color: tokens.border),
        Expanded(
          flex: 2,
          child: Padding(
            padding: EdgeInsets.all(tokens.spacingMd),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: tokens.spacingSm,
              children: [
                Text('Next', style: heading),
                Flexible(
                  flex: 2,
                  child: KeyedSubtree(
                    key: const ValueKey('slide_presenter_next'),
                    child: next == null
                        ? Text(
                            'End of presentation',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: tokens.foreground),
                          )
                        : SlideCanvas.readOnly(
                            slide: next,
                            size: size,
                            theme: theme,
                            imageBuilder: imageBuilder,
                            style: SlideEditorCanvas.styleOf(context),
                          ),
                  ),
                ),
                SlidePresenterClock(elapsed: elapsed),
                Text('Notes', style: heading),
                Expanded(flex: 3, child: SlideNotesView(notes: notes)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
