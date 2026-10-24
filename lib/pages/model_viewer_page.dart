import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/model_viewer_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/model_viewer/model_viewer_body.dart';

/// The 3D model viewer at `/model/<path>` (#2988): an STL, OBJ, PLY, glTF or
/// 3MF file drawn to orbit, pan and zoom, with its size and counts.
///
/// A file the viewer will not draw (over the size, triangle or time cap, or
/// not a valid model) falls back to the file's details and download
/// actions, the same page any file without a viewer gets, with a note
/// saying why.
class ModelViewerPage extends StatefulWidget {
  /// The file's files-relative path.
  final String filePath;

  /// The device the file is on, empty for the internal drive.
  final String deviceSerial;

  /// The viewer's state; a test passes one with fake reads.
  final ModelViewerController? controller;

  const ModelViewerPage({
    required this.filePath,
    this.deviceSerial = '',
    this.controller,
    super.key,
  });

  @override
  State<ModelViewerPage> createState() => _ModelViewerPageState();
}

class _ModelViewerPageState extends State<ModelViewerPage> {
  late final ModelViewerController _controller =
      widget.controller ??
      ModelViewerController(
        path: widget.filePath,
        serial: serialOrNull(widget.deviceSerial),
      );

  @override
  void initState() {
    super.initState();
    _controller
      ..addListener(_announceFallback)
      ..load();
  }

  @override
  void dispose() {
    _controller.removeListener(_announceFallback);
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  void _announceFallback() {
    final fallback = _controller.fallback;
    if (fallback == null || !mounted) return;
    showMessage(context, Errors.modelPreview(fallback));
  }

  @override
  Widget build(BuildContext context) {
    // Nothing underneath is the usual case: Files opens the viewer at its own
    // URL, so leaving goes to the folder that holds the file (#1749).
    final canPop = context.canPop();
    void leave() => context.go(
      AppRoutes.containingFolder(widget.filePath, serial: widget.deviceSerial),
    );
    final name = widget.filePath.split('/').last;

    return PopScope(
      // A system back with nothing underneath would close the app.
      canPop: canPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !canPop) leave();
      },
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _controller.fallback != null
            ? GenericFileViewerPage(
                node: FileNode(
                  name: name,
                  size: _controller.fileSize ?? 0,
                  isDir: false,
                  deviceName: '',
                  devicePath: '',
                  deviceSerial: widget.deviceSerial,
                  dirPath: widget.filePath,
                ),
                onClose: canPop ? context.pop : leave,
              )
            : Scaffold(
                appBar: ChromeAppBar(
                  title: Text(name),
                  leading: BackButton(onPressed: canPop ? context.pop : leave),
                  actions: const [AppThemeToggle()],
                ),
                body: SafeArea(
                  top: false,
                  child: ModelViewerBody(controller: _controller),
                ),
              ),
      ),
    );
  }
}
