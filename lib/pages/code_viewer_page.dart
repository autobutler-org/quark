import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/widgets/code_viewer/code_viewer_body.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/leave_pop_scope.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
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
    final canPop = context.canPop();
    void leave() => context.go(
      AppRoutes.leaveFile(
        context,
        widget.filePath,
        serial: widget.deviceSerial,
      ),
    );

    return LeavePopScope(
      onLeave: leave,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Scaffold(
          appBar: ChromeAppBar(
            title: Text(widget.filePath.split('/').last),
            leading: BackButton(onPressed: canPop ? context.pop : leave),
            actions: [
              Row(
                mainAxisSize: MainAxisSize.min,
                spacing: QuarkTokens.of(context).spacingSm,
                children: [
                  QuarkBarChip(
                    key: const ValueKey('code_viewer_edit'),
                    icon: QuarkIcons.edit_outlined,
                    label: 'Edit',
                    // The editor loads the whole file, so it is only offered
                    // one that has already been read to its end.
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
                  const AppThemeToggle(),
                ],
              ),
            ],
          ),
          body: CodeViewerBody(controller: _controller),
        ),
      ),
    );
  }
}
