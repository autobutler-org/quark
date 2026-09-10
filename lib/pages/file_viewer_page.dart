import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/audio_player_page.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/svg_viewer_page.dart';
import 'package:quark/pages/video_viewer_page.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';

/// A routing shim that resolves a files path to its correct viewer.
///
/// On [initState] it calls [FilesService.statFile] to determine the file
/// type, then immediately navigates to the appropriate page:
///
/// | fileType                         | Destination                     |
/// |----------------------------------|---------------------------------|
/// | `image`                          | [ImageViewerPage]               |
/// | `svg`                            | [SvgViewerPage]                 |
/// | `video`                          | [VideoViewerPage]               |
/// | `audio`                          | [AudioPlayerPage]               |
/// | `qdoc`                          | /docs/&lt;path&gt;              |
/// | `qsheet`                        | /sheets/&lt;path&gt;            |
/// | `text`                           | /edit/&lt;path&gt;              |
/// | `pdf`, `docx`, `epub`, `slideshow`, `xlsx`, `generic` | [GenericFileViewerPage] |
/// | directory                        | /files/&lt;path&gt; (browser)  |
///
/// Navigate to the route built with [AppRoutes.viewFile] to trigger this.
class FileViewerPage extends StatefulWidget {
  final String filePath;
  final String deviceSerial;

  const FileViewerPage({
    required this.filePath,
    this.deviceSerial = '',
    super.key,
  });

  @override
  State<FileViewerPage> createState() => _FileViewerPageState();
}

// ---------------------------------------------------------------------------
// Private helpers — avoids circular import with router.dart
// ---------------------------------------------------------------------------

String _filesPath(String path) {
  final clean = path.replaceAll(RegExp(r'^/+'), '');
  return clean.isEmpty ? '/files' : '/files/\$clean';
}

String _buildRoute(String base, String path, {String? serial}) {
  final clean = path.replaceAll(RegExp(r'^/+'), '');
  final url = '$base/$clean';
  return (serial != null && serial.isNotEmpty)
      ? '$url?serial=${Uri.encodeQueryComponent(serial)}'
      : url;
}

// ---------------------------------------------------------------------------

class _FileViewerPageState extends State<FileViewerPage> {
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _resolveAndNavigate();
  }

  Future<void> _resolveAndNavigate() async {
    try {
      final serial = widget.deviceSerial.trim().isEmpty
          ? null
          : widget.deviceSerial;
      final stat = await FilesService.statFile(widget.filePath, serial: serial);

      if (!mounted) return;

      final name = stat.name.isEmpty
          ? widget.filePath.split('/').last
          : stat.name;

      if (stat.isDir) {
        // Directory — navigate to the file browser.
        context.go(_filesPath(widget.filePath));
        return;
      }

      switch (stat.fileType) {
        case 'image':
          final bytes = await FilesService.downloadFileBytes(
            widget.filePath,
            serial: serial,
          );
          if (!mounted) return;
          if (bytes == null) {
            setState(
              () => _errorMessage = Errors.couldNot('download the image'),
            );
            return;
          }
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => ImageViewerPage(
                bytes: bytes,
                name: name,
                relPath: widget.filePath,
                serial: serial,
              ),
            ),
          );

        case 'svg':
          // SVG is XML, not a raster codec, so it needs SvgPicture rather
          // than the photo viewer's Image.memory (#1806).
          final svgBytes = await FilesService.downloadFileBytes(
            widget.filePath,
            serial: serial,
          );
          if (!mounted) return;
          if (svgBytes == null) {
            setState(
              () => _errorMessage = Errors.couldNot('download the image'),
            );
            return;
          }
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => SvgViewerPage(bytes: svgBytes, name: name),
            ),
          );

        case 'video':
          final videoUrl = FilesService.constructMediaUrl(
            widget.filePath,
            serial: serial,
          );
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => VideoViewerPage(url: videoUrl, name: name),
            ),
          );

        case 'audio':
          final audioUrl = FilesService.constructMediaUrl(
            widget.filePath,
            serial: serial,
          );
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => AudioPlayerPage(url: audioUrl, name: name),
            ),
          );

        case 'qdoc':
          context.go(_buildRoute('/docs', widget.filePath, serial: serial));

        case 'qsheet':
          context.go(_buildRoute('/sheets', widget.filePath, serial: serial));

        case 'text':
          context.push(_buildRoute('/edit', widget.filePath, serial: serial));

        case 'pdf':
        case 'docx':
        case 'epub':
        case 'slideshow':
        // A workbook opened by URL rather than tapped in the browser: the
        // conversion offer lives there, so this is download and "Open with"
        // (#1741).
        case 'xlsx':
        case 'generic':
        default:
          // No dedicated viewer yet — show download + "Open with" actions.
          // This prevents unsupported types from being silently re-routed or
          // misrepresented (e.g. showing a JPEG thumbnail for a .docx file).
          final node = FileNode(
            name: name,
            size: 0,
            isDir: false,
            deviceName: '',
            devicePath: widget.filePath,
            deviceSerial: serial ?? '',
            dirPath: widget.filePath,
            fileType: stat.fileType,
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => GenericFileViewerPage(node: node),
            ),
          );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = Errors.message(e, 'open the file'));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Open File'),
          actions: const [AppThemeToggle()],
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(_errorMessage!, textAlign: TextAlign.center),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/files');
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('Go Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
