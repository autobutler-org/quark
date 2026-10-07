import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/slides/export/slide_export_button.dart';
import 'package:quark/widgets/slides/insert/slide_quark_image_dialog.dart';
import 'package:quark/widgets/slides/properties/slide_properties_panel.dart';
import 'package:quark/widgets/slides/shortcuts/slide_shortcuts_dialog.dart';
import 'package:quark/widgets/slides/shortcuts/slide_shortcuts_help.dart';
import 'package:quark/widgets/slides/slide_editor_bar_bottom.dart';
import 'package:quark/widgets/slides/slide_editor_body.dart';
import 'package:quark/widgets/slides/slide_save_status.dart';
import 'package:quark/widgets/slides/toolbar/slide_phone_toolbar.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The editor for one presentation, at `/slides/<path>?serial=` (#1161): the
/// slide panel to add, duplicate, delete and reorder slides, the canvas
/// editing the selected slide in the middle (#1153) with its zoom in the
/// bar's second row, undo and redo from the bar or the keyboard, and an
/// autosave whose state the bar shows. A failed save says so and keeps the
/// edits for a retry. Each slide's speaker notes are typed under the canvas
/// (#1166).
///
/// Under the bar, the toolbar (#1167) picks drawing tools and formats the
/// selection, and the properties panel sets its position, size and alt
/// text — beside the canvas on a wide screen, in a sheet
/// the page opens on a phone. Pictures (#1158) come from this device,
/// uploaded beside the presentation, or from the Quark through a folder
/// picker the page shows; a failure is a snack bar in the app's words.
///
/// The bar's Present chip, and a slide's "Present from this slide", open
/// the presentation full-window at `/slides/<path>/present` (#1165). The
/// presentation as it is on screen goes along, so nothing waits for the
/// save the chip starts on the way.
///
/// The bar's export button saves the presentation as a PowerPoint file
/// (#1172), saving unsaved edits first; a failure is a snack bar.
///
/// `?` or F1 anywhere in the editor, the toolbar's keyboard button, or
/// "Keyboard shortcuts" in a phone's Format menu opens the shortcuts dialog
/// (#1168).
///
/// Nothing is pushed underneath it when it opens at its own URL, so its back
/// button and a system back land in the folder that holds the file, as the
/// sheet and doc editors do (#1749).
class SlideEditorPage extends StatefulWidget {
  /// Opens the presentation at [filePath] on the device [deviceSerial].
  const SlideEditorPage({
    required this.filePath,
    this.deviceSerial = '',
    this.controller,
    super.key,
  });

  /// The presentation's path, relative to the device's files root.
  final String filePath;

  /// The device the file is on; empty for the Quark's own storage.
  final String deviceSerial;

  /// The page's state, for tests that pass fake services; built from
  /// [filePath] and [deviceSerial] when null.
  final SlideEditorController? controller;

  @override
  State<SlideEditorPage> createState() => _SlideEditorPageState();
}

class _SlideEditorPageState extends State<SlideEditorPage> {
  late final SlideEditorController _controller =
      widget.controller ??
      SlideEditorController(
        filePath: widget.filePath,
        deviceSerial: widget.deviceSerial,
      );

  @override
  void initState() {
    super.initState();
    _controller
      ..onSaveFailed = _reportFailure('save the presentation')
      ..onImageInsertFailed = _reportFailure('add the picture')
      ..onExportFailed = _reportFailure('export the presentation');
    _controller.load();
  }

  @override
  void dispose() {
    _controller.onSaveFailed = null;
    _controller.onImageInsertFailed = null;
    _controller.onExportFailed = null;
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  /// A failure handler that says, in a snack bar, the app couldn't [action].
  void Function(Object error) _reportFailure(String action) => (error) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(Errors.message(error, action))));
  };

  void _leaveForContainingFolder() =>
      context.go(AppRoutes.containingFolder(widget.filePath));

  void _present(String slideId) {
    // Saving first writes notes still waiting for a pause into the
    // presentation handed over.
    unawaited(_controller.save());
    final presentation = _controller.presentation;
    if (presentation == null) return;
    context.go(
      AppRoutes.slidePresent(
        widget.filePath,
        serial: widget.deviceSerial,
        slide: presentation.indexOfSlide(slideId) + 1,
      ),
      extra: presentation,
    );
  }

  Future<void> _insertImageFromQuark() async {
    final path = await SlideQuarkImageDialog.show(
      context,
      startPath: _controller.folderPath,
      listFolder: _controller.listImageFolder,
    );
    if (path != null) await _controller.insertImageFromQuark(path);
  }

  void _showShortcuts() => SlideShortcutsDialog.show(context);

  void _openPropertiesSheet() => showQuarkSheet<void>(
    context,
    title: 'Properties',
    builder: (_) => ListenableBuilder(
      listenable: _controller,
      builder: (_, _) => SlidePropertiesPanel(controller: _controller),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return PopScope(
      // With nothing underneath, a system back would close the app; it
      // leaves for the containing folder, as the bar's back button does.
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) _leaveForContainingFolder();
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            leading: canPop
                ? null
                : BackButton(onPressed: _leaveForContainingFolder),
            title: Text(
              fileNameWithoutExtension(
                widget.filePath,
                SlidesService.extension,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: QuarkTokens.of(context).spacingSm,
                children: [
                  QuarkBarIconButton(
                    key: const ValueKey('slide_editor_undo'),
                    icon: QuarkIcons.undo,
                    tooltip: 'Undo',
                    onPressed: _controller.canUndo ? _controller.undo : null,
                  ),
                  QuarkBarIconButton(
                    key: const ValueKey('slide_editor_redo'),
                    icon: QuarkIcons.redo,
                    tooltip: 'Redo',
                    onPressed: _controller.canRedo ? _controller.redo : null,
                  ),
                  SlideSaveStatus(
                    state: _controller.saveState,
                    onSave: _controller.save,
                  ),
                  SlideExportButton(
                    isExporting: _controller.isExporting,
                    onPressed: _controller.presentation == null
                        ? null
                        : _controller.exportPptx,
                  ),
                  QuarkBarChip(
                    key: const ValueKey('slide_editor_present'),
                    icon: QuarkIcons.play_arrow,
                    label: 'Present',
                    tooltip: 'Present from the first slide',
                    onPressed: _controller.slides.isEmpty
                        ? null
                        : () => _present(_controller.slides.first.id),
                  ),
                  const AppThemeToggle(),
                ],
              ),
            ],
            bottom: _controller.presentation == null
                ? null
                : SlideEditorBarBottom(
                    position:
                        'Slide ${_controller.selectedIndex + 1} of '
                        '${_controller.slides.length}',
                    zoomPercent: _controller.zoomPercent,
                    onZoomIn: _controller.canZoomIn ? _controller.zoomIn : null,
                    onZoomOut: _controller.canZoomOut
                        ? _controller.zoomOut
                        : null,
                    onFit: _controller.zoomToFit,
                    phoneTools: SlidePhoneToolbar(
                      controller: _controller,
                      onImageFromDevice: _controller.insertImageFromDevice,
                      onImageFromQuark: _insertImageFromQuark,
                      onOpenProperties: _openPropertiesSheet,
                      onShowShortcuts: _showShortcuts,
                    ),
                  ),
          ),
          body: SafeArea(
            top: false,
            child: SlideShortcutsHelp(
              child: SlideEditorBody(
                controller: _controller,
                onPresent: _present,
                onImageFromDevice: _controller.insertImageFromDevice,
                onImageFromQuark: _insertImageFromQuark,
                onShowShortcuts: _showShortcuts,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
