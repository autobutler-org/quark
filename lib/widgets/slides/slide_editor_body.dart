import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/widgets/slides/insert/slide_image_upload_status.dart';
import 'package:quark/widgets/slides/notes/slide_notes_panel.dart';
import 'package:quark/widgets/slides/properties/slide_properties_panel.dart';
import 'package:quark/widgets/slides/slide_editor_canvas.dart';
import 'package:quark/widgets/slides/find/slide_find_provider.dart';
import 'package:quark/widgets/slides/slide_editor_shortcuts.dart';
import 'package:quark/widgets/slides/slide_image.dart';
import 'package:quark/widgets/slides/slide_panel.dart';
import 'package:quark/widgets/slides/slides_error_view.dart';
import 'package:quark/widgets/slides/toolbar/slide_toolbar.dart';
import 'package:quark_slides/quark_slides.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Everything under the slide editor's bar: the loader, the load error, or
/// the [SlideToolbar] across the top (#1167) over the [SlidePanel] beside
/// the [SlideEditorCanvas] editing the selected slide, with the slide's
/// speaker notes ([SlideNotesPanel]) under the canvas, the
/// [SlidePropertiesPanel] down the right on a wide screen, and the undo
/// and redo keys over all of it ([SlideEditorShortcuts]). While a picture
/// uploads, a [SlideImageUploadStatus] sits over the canvas.
///
/// The properties panel goes beside the canvas where the toolbar shows its
/// two rows — at [QuarkAppBarBottom.collapseBreakpoint] and wider — and is
/// hidden by the toolbar's toggle; narrower, the page shows it as a sheet
/// from the phone toolbar in its bar.
///
/// The open notes field gives up height before the canvas shrinks below one
/// touch target, so a phone with its keyboard up keeps a sliver of slide.
///
/// A slide's menu offers presenting from it through [onPresent], and its
/// Delete goes through [onDeleteSlide].
///
/// Pictures on the canvas and the thumbnails are [SlideImage]s fetched
/// through the Quark's authenticated download URL for their path
/// ([SlideEditorController.imageUrl]); an animated one plays on the canvas
/// and holds its first frame in a thumbnail.
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
  const SlideEditorBody({
    required this.controller,
    required this.onImageFromDevice,
    required this.onImageFromQuark,
    required this.onShowShortcuts,
    required this.onDeleteSlide,
    this.onPresent,
    super.key,
  });

  /// The open presentation.
  final SlideEditorController controller;

  /// Presents from the slide with the given id; null leaves the slide menu
  /// without the row.
  final ValueChanged<String>? onPresent;

  /// Picks a picture on this device for the selected slide.
  final VoidCallback onImageFromDevice;

  /// Picks a picture already on the Quark for the selected slide.
  final VoidCallback onImageFromQuark;

  /// Opens the keyboard shortcuts dialog.
  final VoidCallback onShowShortcuts;

  /// Deletes the slide with the given id from its menu; the page deletes it
  /// and offers Undo (#2897).
  final ValueChanged<String> onDeleteSlide;

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
    final find = SlideFindProvider.maybeOf(context);
    final collapsed = QuarkSplitView.isCollapsed(context);
    // The thumbnails hold an animated picture's first frame (#2866).
    SlideImageBuilder imageBuilder({required bool animate}) =>
        (context, image) => SlideImage(
          image: NetworkImage(c.imageUrl(image.source).toString()),
          fit: image.fit,
          animate: animate,
        );
    final panel = SlidePanel(
      slides: presentation.slides,
      size: presentation.size,
      selectedSlideId: c.selectedSlideId,
      axis: collapsed ? Axis.horizontal : Axis.vertical,
      canDelete: c.canDeleteSlide,
      onSelect: c.selectSlide,
      onAdd: c.addSlide,
      onAddWithLayout: (layoutId) => c.addSlide(layoutId: layoutId),
      layouts: c.layouts,
      theme: presentation.theme,
      defaultTransition: presentation.defaultTransition,
      onDuplicate: c.duplicateSlide,
      onDelete: onDeleteSlide,
      onMove: c.moveSlide,
      onSelectPrevious: c.selectPreviousSlide,
      onSelectNext: c.selectNextSlide,
      imageBuilder: imageBuilder(animate: false),
      onPresent: onPresent,
      readOnly: c.isReadOnly,
    );
    final slideId = c.selectedSlideId;
    final upload = c.imageUpload;
    final stage = LayoutBuilder(
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (upload != null)
            SlideImageUploadStatus(
              name: upload.name,
              progress: upload.progress,
            ),
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('slide_editor_stage'),
              child: SlideEditorCanvas(
                controller: c,
                imageBuilder: imageBuilder(animate: true),
              ),
            ),
          ),
          if (slideId != null)
            SlideNotesPanel(
              slideId: slideId,
              notes: c.notes,
              open: c.notesOpen,
              onToggle: c.toggleNotes,
              onChanged: c.editNotes,
              readOnly: c.isReadOnly,
              fieldHeight:
                  (constraints.maxHeight - 2 * SlideNotesPanel.headerHeight)
                      .clamp(0, SlideNotesPanel.maxFieldHeight),
            ),
        ],
      ),
    );

    final editor = collapsed
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

    return SlideEditorShortcuts(
      onUndo: c.undo,
      onRedo: c.redo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SlideToolbar(
            controller: c,
            onImageFromDevice: onImageFromDevice,
            onImageFromQuark: onImageFromQuark,
            onShowShortcuts: onShowShortcuts,
            findOpen: find?.isOpen ?? false,
            onToggleFind: find?.toggle ?? () {},
          ),
          Expanded(
            // The canvas stays the first child whether or not the panel
            // shows, so toggling it keeps the canvas's state.
            child: LayoutBuilder(
              builder: (context, constraints) => Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: editor),
                  if (c.propertiesOpen &&
                      !SlideToolbar.isCompact(constraints.maxWidth)) ...[
                    VerticalDivider(width: 1, color: tokens.border),
                    SizedBox(
                      width: SlidePropertiesPanel.sideWidth,
                      child: SingleChildScrollView(
                        child: SlidePropertiesPanel(controller: c),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
