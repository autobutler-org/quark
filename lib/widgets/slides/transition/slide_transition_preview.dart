import 'package:flutter/material.dart';
import 'package:quark/widgets/slides/slide_editor_canvas.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A small stage showing the slide, with a "Preview" button that plays
/// [transition] once on it, from the slide before into this one (#1164). The
/// first slide arrives from a blank one.
///
/// The slides are read-only [SlideCanvas]es inside a [SlideTransitionView],
/// which honors reduced motion by itself. At rest the stage shows [slide].
///
/// Key prefixes: `slide_transition_preview` on the button and
/// `slide_transition_stage` on the stage.
class SlideTransitionPreview extends StatefulWidget {
  /// The preview of [transition] arriving at [slide] from [previous].
  const SlideTransitionPreview({
    required this.slide,
    required this.previous,
    required this.size,
    required this.transition,
    this.theme,
    this.imageBuilder,
    super.key,
  });

  /// The slide the transition arrives at.
  final Slide slide;

  /// The slide before it; null for the first slide.
  final Slide? previous;

  /// The presentation's slide size.
  final SlideSize size;

  /// The transition to play.
  final SlideTransitionSpec transition;

  /// The presentation's theme; null for none.
  final SlideTheme? theme;

  /// Draws image elements and background images.
  final SlideImageBuilder? imageBuilder;

  @override
  State<SlideTransitionPreview> createState() => _SlideTransitionPreviewState();
}

class _SlideTransitionPreviewState extends State<SlideTransitionPreview> {
  static const _blankId = 'slide_transition_blank';

  /// Whether the stage shows the slide before, the moment before a play.
  bool _fromPrevious = false;

  /// Counts plays, so each starts a fresh view that simply shows the slide
  /// before and then changes to this one.
  int _plays = 0;

  void _play() {
    setState(() {
      _plays++;
      _fromPrevious = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _fromPrevious = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final slide = _fromPrevious
        ? widget.previous ?? Slide(id: _blankId)
        : widget.slide;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: tokens.spacingSm,
      children: [
        Container(
          key: const ValueKey('slide_transition_stage'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(tokens.radiusSm),
            border: Border.all(color: tokens.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: ExcludeSemantics(
            child: SlideTransitionView(
              key: ValueKey(_plays),
              slideId: slide.id,
              transition: widget.transition,
              child: SlideCanvas.readOnly(
                slide: slide,
                size: widget.size,
                theme: widget.theme,
                imageBuilder: widget.imageBuilder,
                style: SlideEditorCanvas.styleOf(context),
              ),
            ),
          ),
        ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: QuarkBarChip(
            key: const ValueKey('slide_transition_preview'),
            icon: QuarkIcons.play_arrow_rounded,
            label: 'Preview',
            tooltip: 'Play this transition once',
            keepLabel: true,
            onPressed: _play,
          ),
        ),
      ],
    );
  }
}
