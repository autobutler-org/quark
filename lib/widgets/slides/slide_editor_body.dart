import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/slide_editor_canvas.dart';
import 'package:quark/widgets/slides/slide_editor_shortcuts.dart';
import 'package:quark/widgets/slides/slide_image.dart';
import 'package:quark/widgets/slides/slide_panel.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the slide editor's bar: the loader, the load error, or
/// the [SlidePanel] beside the [SlideEditorCanvas] editing the selected
/// slide, with the undo and redo keys over both ([SlideEditorShortcuts]).
///
/// Pictures on the canvas and the thumbnails are [SlideImage]s fetched
/// through the Quark's authenticated download URL for their path
/// ([SlideEditorController.imageUrl]).
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
    Widget imageBuilder(BuildContext context, SlideImageSource image) =>
        SlideImage(
          image: NetworkImage(c.imageUrl(image.source).toString()),
          fit: image.fit,
        );
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
      onSelectPrevious: c.selectPreviousSlide,
      onSelectNext: c.selectNextSlide,
      imageBuilder: imageBuilder,
    );
    final stage = KeyedSubtree(
      key: const ValueKey('slide_editor_stage'),
      child: SlideEditorCanvas(controller: c, imageBuilder: imageBuilder),
    );

    return SlideEditorShortcuts(
      onUndo: c.undo,
      onRedo: c.redo,
      child: collapsed
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
            ),
    );
  }
}
