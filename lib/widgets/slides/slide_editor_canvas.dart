import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The middle of the slide editor: the package's [SlideCanvas] editing the
/// selected slide of [controller]'s document (#1153).
///
/// The canvas's element selection and zoom are the controller's, so the bar's
/// zoom buttons, the slide panel and anything else reading the controller
/// agree with what the canvas shows. Its edits go straight to the document,
/// which is how they reach undo and the autosave.
///
/// It takes focus when it is built and whenever it is pressed, so its
/// arrow, Delete, Tab and stacking keys work at once; Ctrl or Cmd Z is not
/// one of them, so it reaches the editor's undo shortcut above.
///
/// The bar's second row says which slide it is; the canvas names each
/// element to a screen reader. Colors come from [styleOf].
///
/// Key prefixes: `slide_editor_canvas` on the canvas, and the package's
/// `slide_element_<id>` and `slide_handle_<name>` inside it.
class SlideEditorCanvas extends StatelessWidget {
  /// Edits [controller]'s selected slide, drawing pictures with
  /// [imageBuilder].
  const SlideEditorCanvas({
    required this.controller,
    required this.imageBuilder,
    super.key,
  });

  /// The open presentation.
  final SlideEditorController controller;

  /// Draws image elements and background images.
  final SlideImageBuilder imageBuilder;

  /// The canvas chrome in the app's tokens: selection and handles in the
  /// primary color, snap guides in the warning color, the letterbox in the
  /// page background. Slide content keeps its own colors.
  static SlideCanvasStyle styleOf(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return SlideCanvasStyle.fromTheme(Theme.of(context)).copyWith(
      selectionColor: tokens.primary,
      handleFillColor: tokens.card,
      guideColor: tokens.warning,
      backdropColor: tokens.background,
      placeholderColor: tokens.mutedForeground,
    );
  }

  @override
  Widget build(BuildContext context) {
    final document = controller.document;
    final slideId = controller.selectedSlideId;
    if (document == null || slideId == null) return const SizedBox.expand();
    return SlideCanvas(
      key: const ValueKey('slide_editor_canvas'),
      document: document,
      slideId: slideId,
      selection: controller.selectedElementIds,
      onSelectionChanged: controller.selectElements,
      zoom: controller.zoom,
      onZoomChanged: controller.setZoom,
      imageBuilder: imageBuilder,
      style: styleOf(context),
      autofocus: true,
    );
  }
}
