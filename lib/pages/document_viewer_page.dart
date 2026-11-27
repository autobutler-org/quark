import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/document_viewer_controller.dart';
import 'package:quark/router.dart';
import 'package:quark/utils/document_viewer_files.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark/widgets/document_viewer/document_convert_conflict_dialog.dart';
import 'package:quark/widgets/document_viewer/document_converted_dialog.dart';
import 'package:quark/widgets/document_viewer/document_viewer_body.dart';
import 'package:quark/widgets/layout/file_route_chrome.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// The read-only document viewer at `/document/<path>` (#3265): a `.docx`,
/// `.docm`, `.odt` or `.rtf` file with its headings, lists, tables and
/// pictures, as the Quark read it.
///
/// "Open as Quark doc" writes the document as a `.qdoc` beside it and opens
/// that in the editor; the original is never changed. When that `.qdoc` is
/// already there the reader chooses between it and a fresh copy, and when the
/// copy could not hold everything they are told what was left out first.
/// Download saves the original. A link opens in the browser or mail app, and
/// only an `http`, `https` or `mailto` one.
///
/// Keys: `document_viewer_open_as_doc` and `document_viewer_download`.
class DocumentViewerPage extends StatefulWidget {
  /// The file's files-relative path.
  final String filePath;

  /// The device the file is on, empty for the internal drive.
  final String deviceSerial;

  /// The viewer's state; a test passes one with fake reads.
  final DocumentViewerController? controller;

  /// Opens a link outside the app; a test passes a recorder.
  final void Function(Uri uri) openExternal;

  const DocumentViewerPage({
    required this.filePath,
    this.deviceSerial = '',
    this.controller,
    this.openExternal = _launchExternal,
    super.key,
  });

  static void _launchExternal(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  State<DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<DocumentViewerPage> {
  late final DocumentViewerController _controller =
      widget.controller ??
      DocumentViewerController(
        path: widget.filePath,
        serial: serialOrNull(widget.deviceSerial),
      );

  String get _name => widget.filePath.split('/').last;

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

  void _openLink(String href) {
    final uri = Uri.tryParse(href.trim());
    if (uri == null) return;
    if (uri.isScheme('http') ||
        uri.isScheme('https') ||
        uri.isScheme('mailto')) {
      widget.openExternal(uri);
    }
  }

  void _openDoc(String path) => context.go(
    AppRoutes.docFile(
      path,
      serial: widget.deviceSerial,
      // Back from the editor returns here.
      from: GoRouterState.of(context).uri.toString(),
    ),
  );

  Future<void> _convert({bool overwrite = false}) async {
    try {
      final result = await _controller.convert(overwrite: overwrite);
      if (!mounted) return;
      final open =
          (result.warnings.isEmpty && !result.truncated) ||
          await showDialog<bool>(
                context: context,
                builder: (_) => DocumentConvertedDialog(
                  qdocName: result.path.split('/').last,
                  warnings: result.warnings,
                  truncated: result.truncated,
                ),
              ) ==
              true;
      if (open && mounted) _openDoc(result.path);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 409 && !overwrite) {
        await _resolveConflict();
        return;
      }
      showMessage(context, Errors.message(e, 'convert the document'));
    }
  }

  /// The `.qdoc` is already there: open it, replace it, or leave both alone.
  Future<void> _resolveConflict() async {
    final existing = siblingQdocPath(widget.filePath);
    final choice = await showDialog<DocumentConvertConflictChoice>(
      context: context,
      builder: (_) => DocumentConvertConflictDialog(
        qdocName: existing.split('/').last,
        sourceName: _name,
      ),
    );
    if (!mounted) return;
    switch (choice) {
      case DocumentConvertConflictChoice.replace:
        await _convert(overwrite: true);
      case DocumentConvertConflictChoice.openExisting:
        _openDoc(existing);
      case null:
        break;
    }
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
            key: const ValueKey('document_viewer_open_as_doc'),
            icon: QuarkIcons.edit_document,
            label: 'Open as Quark doc',
            tooltip: 'Open as Quark doc',
            onPressed: _controller.canConvert ? _convert : null,
          ),
          QuarkBarIconButton(
            key: const ValueKey('document_viewer_download'),
            icon: QuarkIcons.download_outlined,
            tooltip: 'Download',
            onPressed: () => downloadViewedFile(
              context,
              path: widget.filePath,
              serial: serialOrNull(widget.deviceSerial),
              name: _name,
            ),
          ),
        ],
        body: SafeArea(
          top: false,
          child: DocumentViewerBody(
            controller: _controller,
            onLinkTap: _openLink,
          ),
        ),
      ),
    );
  }
}
