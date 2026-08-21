import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quark/models/cirrus_file_node.dart';
import 'package:quark/pages/generic_file_viewer_page.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/services/cirrus_service.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';

/// A routing shim that resolves a Cirrus file path to its correct viewer.
///
/// On [initState] it calls [CirrusService.statFile] to determine the file
/// type, then immediately navigates to the appropriate page:
///
/// | fileType                         | Destination                     |
/// |----------------------------------|---------------------------------|
/// | `image`                          | [ImageViewerPage]               |
/// | `video`                          | /videos/&lt;path&gt;            |
/// | `audio`                          | /audio/&lt;path&gt;             |
/// | `abdoc`                          | /docs/&lt;path&gt;              |
/// | `absheet`                        | /sheets/&lt;path&gt;            |
/// | `text`                           | /edit/&lt;path&gt;              |
/// | `pdf`, `docx`, `epub`, `slideshow`, `generic` | [GenericFileViewerPage] |
/// | directory                        | /cirrus/&lt;path&gt; (browser)  |
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

String _cirrusPath(String path) {
  final clean = path.replaceAll(RegExp(r'^/+'), '');
  return clean.isEmpty ? '/cirrus' : '/cirrus/$clean';
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
      final stat = await CirrusService.statFile(
        widget.filePath,
        serial: serial,
      );

      if (!mounted) return;

      final name = stat.name.isEmpty
          ? widget.filePath.split('/').last
          : stat.name;

      if (stat.isDir) {
        // Directory — navigate to the file browser.
        context.go(_cirrusPath(widget.filePath));
        return;
      }

      switch (stat.fileType) {
        case 'image':
          final bytes = await CirrusService.downloadFileBytes(
            widget.filePath,
            serial: serial,
          );
          if (!mounted) return;
          if (bytes == null) {
            setState(() => _errorMessage = 'Failed to download image.');
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

        case 'video':
          if (!mounted) return;
          // Use the named route so the URL bar reflects the viewer path and
          // the link is shareable / deep-linkable.
          context.go(_buildRoute('/videos', widget.filePath, serial: serial));

        case 'audio':
          if (!mounted) return;
          context.go(_buildRoute('/audio', widget.filePath, serial: serial));

        case 'abdoc':
          context.go(_buildRoute('/docs', widget.filePath, serial: serial));

        case 'absheet':
          context.go(_buildRoute('/sheets', widget.filePath, serial: serial));

        case 'text':
          context.push(_buildRoute('/edit', widget.filePath, serial: serial));

        case 'pdf':
        case 'docx':
        case 'epub':
        case 'slideshow':
        case 'generic':
        default:
          // No dedicated viewer yet — show download + "Open with" actions.
          // This prevents unsupported types from being silently re-routed or
          // misrepresented (e.g. showing a JPEG thumbnail for a .docx file).
          final node = CirrusFileNode(
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
        setState(() => _errorMessage = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Open File'),
          actions: const [ThemeToggleButton()],
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
                      context.go('/cirrus');
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
