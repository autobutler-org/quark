import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/slide_panel.dart';
import 'package:quark/widgets/slides/slide_stage.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the slide editor's bar: the loader, the load error, or
/// the [SlidePanel] beside the selected slide on its stage.
///
/// The panel runs down the side of a wide window and across the top of a
/// phone, switching at [QuarkSplitView.collapseBreakpoint] so the editor
/// collapses where every other sidebar in the app does.
///
/// It reads [controller] and calls its commands; the page owns the
/// controller.
///
/// Key prefixes: `slide_editor_stage` on the center area.
class SlideEditorBody extends StatelessWidget {
  /// Shows [controller]'s presentation.
  const SlideEditorBody({required this.controller, super.key});

  /// The open presentation.
  final SlideEditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final error = c.loadError;
    final presentation = c.presentation;
    if (c.isLoading) return const Center(child: QuarkLoader());
    if (error != null || presentation == null) {
      return SlidesErrorView(
        error: error ?? StateError('no presentation'),
        action: 'open the presentation',
        onRetry: c.load,
      );
    }

    final tokens = QuarkTokens.of(context);
    final collapsed = QuarkSplitView.isCollapsed(context);
    final selected = c.selectedSlide;
    final panel = SlidePanel(
      slides: presentation.slides,
      size: presentation.size,
      selectedSlideId: c.selectedSlideId,
      axis: collapsed ? Axis.horizontal : Axis.vertical,
      canDelete: c.canDeleteSlide,
      onSelect: c.selectSlide,
      onAdd: c.addSlide,
      onDuplicate: c.duplicateSlide,
      onDelete: c.deleteSlide,
      onMove: c.moveSlide,
    );
    final stage = Padding(
      key: const ValueKey('slide_editor_stage'),
      padding: EdgeInsets.all(tokens.spacingLg),
      child: Center(
        child: selected == null
            ? const SizedBox.shrink()
            : DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: tokens.border),
                ),
                child: SlideStage(
                  slide: selected,
                  size: presentation.size,
                  semanticLabel:
                      'Slide ${c.selectedIndex + 1} of '
                      '${presentation.slides.length}',
                ),
              ),
      ),
    );

    return collapsed
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: SlidePanel.stripHeight, child: panel),
              Divider(height: 1, color: tokens.border),
              Expanded(child: stage),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(width: SlidePanel.sideWidth, child: panel),
              VerticalDivider(width: 1, color: tokens.border),
              Expanded(child: stage),
            ],
          );
  }
}
