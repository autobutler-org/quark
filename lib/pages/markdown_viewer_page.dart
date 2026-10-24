import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/controllers/code_viewer_controller.dart';
import 'package:quark/controllers/markdown_viewer_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/markdown_viewer_files.dart';
import 'package:quark/widgets/code_viewer/code_viewer_body.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/widgets/layout/leave_pop_scope.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/markdown_viewer/markdown_viewer_body.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// A read-only viewer for Markdown files (#2987): the rendered document, with
/// a toggle to its source.
///
/// Raw HTML in the file shows as text, and an image on the web loads only
/// when the reader asks. A link to another file on the Quark opens it; a web
/// link opens in the browser. "Edit" hands the file to the plaintext editor.
class MarkdownViewerPage extends StatefulWidget {
  /// The file's files-relative path.
  final String filePath;

  /// The device the file is on, empty for the internal drive.
  final String deviceSerial;

  /// The state behind the rendered view; a test passes one with a fake
  /// reader.
  final MarkdownViewerController? controller;

  /// The state behind the source view; a test passes one with a fake reader.
  final CodeViewerController? sourceController;

  /// Opens a web link; a test passes a recorder.
  final void Function(Uri uri) openExternal;

  const MarkdownViewerPage({
    required this.filePath,
    this.deviceSerial = '',
    this.controller,
    this.sourceController,
    this.openExternal = _launchExternal,
    super.key,
  });

  static void _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  State<MarkdownViewerPage> createState() => _MarkdownViewerPageState();
}

class _MarkdownViewerPageState extends State<MarkdownViewerPage> {
  late final MarkdownViewerController _controller =
      widget.controller ??
      MarkdownViewerController(
        path: widget.filePath,
        serial: serialOrNull(widget.deviceSerial),
      );

  // Created, and the file read a second time, only once the source is asked
  // for.
  late final CodeViewerController _source =
      (widget.sourceController ??
            CodeViewerController(
              path: widget.filePath,
              serial: serialOrNull(widget.deviceSerial),
            ))
        ..load();
  bool _sourceOpened = false;

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    if (_sourceOpened && widget.sourceController == null) _source.dispose();
    super.dispose();
  }

  void _toggleSource() {
    _sourceOpened = true;
    _controller.setShowSource(!_controller.showSource);
  }

  void _openLink(String href) {
    final target = resolveMarkdownLink(widget.filePath, href);
    switch (target.kind) {
      case MarkdownLinkKind.file:
        context.go(
          AppRoutes.viewFilePath(target.value, serial: widget.deviceSerial),
        );
      case MarkdownLinkKind.remote:
        widget.openExternal(Uri.parse(target.value));
      case MarkdownLinkKind.other:
        break;
    }
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
                    key: const ValueKey('markdown_viewer_source_toggle'),
                    icon: _controller.showSource
                        ? QuarkIcons.visibility_outlined
                        : QuarkIcons.text_box,
                    label: _controller.showSource ? 'Rendered' : 'Source',
                    onPressed: _toggleSource,
                  ),
                  QuarkBarChip(
                    key: const ValueKey('markdown_viewer_edit'),
                    icon: QuarkIcons.edit_outlined,
                    label: 'Edit',
                    // The editor loads the whole file, so it is only offered
                    // one the viewer could read whole.
                    onPressed:
                        _controller.isLoading ||
                            _controller.error != null ||
                            _controller.isTruncated
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
          body: _controller.showSource
              ? ListenableBuilder(
                  listenable: _source,
                  builder: (context, _) => CodeViewerBody(controller: _source),
                )
              : MarkdownViewerBody(
                  controller: _controller,
                  onLinkTap: _openLink,
                ),
        ),
      ),
    );
  }
}
