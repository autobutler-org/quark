import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/widgets/code_viewer/code_viewer_body.dart';
import 'package:quark/widgets/layout/file_route_chrome.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A read-only viewer for source, config and log files (#2991): syntax
/// highlighting, line numbers, a wrap toggle and in-file search.
///
/// The file is read a page at a time, so a log too large to load whole still
/// opens. "Edit" hands a file that has been read to its end over to the
/// plaintext editor, which loads all of it.
class CodeViewerPage extends StatefulWidget {
  /// The file's files-relative path.
  final String filePath;

  /// The device the file is on, empty for the internal drive.
  final String deviceSerial;

  /// The state behind the page; a test passes one with a fake reader.
  final CodeViewerController? controller;

  const CodeViewerPage({
    required this.filePath,
    this.deviceSerial = '',
    this.controller,
    super.key,
  });

  @override
  State<CodeViewerPage> createState() => _CodeViewerPageState();
}

class _CodeViewerPageState extends State<CodeViewerPage> {
  late final CodeViewerController _controller =
      widget.controller ??
      CodeViewerController(
        path: widget.filePath,
        serial: serialOrNull(widget.deviceSerial),
      );

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => FileRouteChrome(
        filePath: widget.filePath,
        deviceSerial: widget.deviceSerial,
        actions: [
          QuarkBarChip(
            key: const ValueKey('code_viewer_edit'),
            icon: QuarkIcons.edit_outlined,
            label: 'Edit',
            // The editor loads the whole file, so it is only offered one that
            // has already been read to its end.
            onPressed:
                _controller.isLoading ||
                    _controller.error != null ||
                    _controller.hasMore
                ? null
                : () => context.go(
                    AppRoutes.plaintextEditorPath(
                      widget.filePath,
                      serial: widget.deviceSerial,
                      // Back from the editor returns here (#3186).
                      from: GoRouterState.of(context).uri.toString(),
                    ),
                  ),
          ),
        ],
        body: CodeViewerBody(controller: _controller),
      ),
    );
  }
}
