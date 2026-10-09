import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/pdf_viewer_page.dart';
import 'package:quark/pages/svg_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';

/// The page at `/view/<path>`: the viewer for one file, picked by its kind.
///
/// Every kind with an in-app viewer opens here rather than being pushed over
/// the file browser, so the address bar names the file, a reload or a shared
/// link reopens it, and browser back closes it (#2328). Docs, sheets and text
/// never get here: `viewFileRedirect` sends them to their editors.
///
/// Closing the viewer — its back button, Escape in the photo viewer, a system
/// back — replaces this history entry with the page the URL's `?from=` names
/// (#1678), or the file's folder without one, so browser back from there
/// never bounces into the viewer again.
class FileViewerPage extends StatefulWidget {
  /// The file's path on the Quark, as the route's `:path` delivers it.
  final String filePath;

  /// The device the file is on; empty lets the Quark pick.
  final String serial;

  /// Fetches an SVG's markup. A parameter so a test can answer without a
  /// Quark.
  final Future<Uint8List?> Function(String filePath, {String? serial})
  downloadBytes;

  const FileViewerPage({
    super.key,
    required this.filePath,
    this.serial = '',
    this.downloadBytes = FilesService.downloadFileBytes,
  });

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

class _FileViewerPageState extends State<FileViewerPage> {
  late final String _name = widget.filePath.split('/').last;
  late final FileKind _kind = fileKindForName(_name);
  late final String? _serial = widget.serial.isEmpty ? null : widget.serial;

  /// SVG is XML for `SvgPicture`, not bytes the photo viewer fetches itself
  /// (#1806), so this page fetches it.
  late final Future<Uint8List?>? _svgBytes = _kind == FileKind.svg
      ? widget.downloadBytes(widget.filePath, serial: _serial)
      : null;

  late final Uri _mediaUrl = FilesService.constructMediaUrl(
    widget.filePath,
    serial: _serial,
  );

  /// A system back reaches both this page's scope and the photo viewer's own.
  bool _closed = false;

  void _close() {
    if (_closed) return;
    _closed = true;
    Router.neglect(
      context,
      () => context.go(
        AppRoutes.editorOrigin(context) ??
            AppRoutes.containingFolder(widget.filePath, serial: widget.serial),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: switch (_kind) {
        FileKind.image => ImageViewerPage(
          name: _name,
          relPath: widget.filePath,
          serial: _serial,
          onClose: _close,
        ),
        FileKind.svg => FutureBuilder<Uint8List?>(
          future: _svgBytes,
          builder: (context, snapshot) => SvgViewerPage(
            bytes: snapshot.data,
            name: _name,
            error:
                snapshot.connectionState == ConnectionState.done &&
                    snapshot.data == null
                ? Errors.message(snapshot.error, 'open the file')
                : null,
            onClose: _close,
          ),
        ),
        // Audio has no video track, so the video viewer paints only its black
        // backdrop (#1573).
        FileKind.audio => AudioPlayerPage(
          url: _mediaUrl,
          name: _name,
          onClose: _close,
        ),
        FileKind.video => VideoViewerPage(
          url: _mediaUrl,
          name: _name,
          onClose: _close,
        ),
        FileKind.pdf => PdfViewerPage(
          filePath: widget.filePath,
          serial: _serial,
          name: _name,
          onClose: _close,
        ),
        _ => GenericFileViewerPage(
          node: FileNode(
            name: _name,
            size: 0,
            isDir: false,
            deviceName: '',
            devicePath: '',
            deviceSerial: widget.serial,
            dirPath: widget.filePath,
          ),
          onClose: _close,
        ),
      },
    );
  }
}
