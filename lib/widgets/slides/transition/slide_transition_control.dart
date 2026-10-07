import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/slide_image.dart';
import 'package:quark/widgets/slides/transition/slide_transition_direction_field.dart';
import 'package:quark/widgets/slides/transition/slide_transition_duration_field.dart';
import 'package:quark/widgets/slides/transition/slide_transition_kind_field.dart';
import 'package:quark/widgets/slides/transition/slide_transition_preview.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The transition picker wired to [controller]'s selected slide (#1164): the
/// kind, the direction (for a push or wipe), the length, a preview, and
/// "Apply to all slides". Each change is one undo step that starts the
/// autosave. The properties panel, the toolbar's Transition menu and a
/// phone's Transition sheet all show this one.
///
/// A view-only presentation shows the slide's transition and the preview,
/// with the choices off.
///
/// Key prefixes: `slide_transition_apply_all` on the apply button, and the
/// fields' and preview's own.
class SlideTransitionControl extends StatelessWidget {
  /// The transition picker for [controller]'s selected slide.
  const SlideTransitionControl({required this.controller, super.key});

  /// The open presentation.
  final SlideEditorController controller;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final presentation = controller.presentation;
    final slide = controller.selectedSlide;
    if (presentation == null || slide == null) return const SizedBox.shrink();
    final transition = controller.effectiveTransition;
    final editable = !controller.isReadOnly;
    final index = controller.selectedIndex;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      spacing: tokens.spacingMd,
      children: [
        SlideTransitionKindField(
          kind: transition.kind,
          onChanged: editable
              ? (kind) => controller.setSlideTransition(
                  transition.copyWith(kind: kind),
                )
              : null,
        ),
        if (transition.kind.isDirectional)
          SlideTransitionDirectionField(
            direction: transition.direction,
            onChanged: editable
                ? (direction) => controller.setSlideTransition(
                    transition.copyWith(direction: direction),
                  )
                : null,
          ),
        if (transition.kind != SlideTransitionKind.none)
          SlideTransitionDurationField(
            durationMs: transition.durationMs,
            onChanged: editable
                ? (ms) => controller.setSlideTransition(
                    transition.copyWith(durationMs: ms),
                  )
                : null,
          ),
        SlideTransitionPreview(
          slide: slide,
          previous: index > 0 ? presentation.slides[index - 1] : null,
          size: presentation.size,
          theme: presentation.theme,
          transition: transition,
          imageBuilder: (context, image) => SlideImage(
            image: NetworkImage(controller.imageUrl(image.source).toString()),
            fit: image.fit,
          ),
        ),
        if (editable)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: QuarkBarChip(
              key: const ValueKey('slide_transition_apply_all'),
              icon: QuarkIcons.slide_transition,
              label: 'Apply to all slides',
              tooltip: 'Use this transition on every slide',
              keepLabel: true,
              onPressed: () => controller.applyTransitionToAll(transition),
            ),
          ),
      ],
    );
  }
}
