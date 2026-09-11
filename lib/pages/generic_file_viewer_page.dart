import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/pages/generic_file_viewer_open_stub.dart'
    if (dart.library.io) 'package:quark/pages/generic_file_viewer_open_native.dart'
    as native_open;
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/files_route_path_utils.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

class GenericFileViewerPage extends StatefulWidget {
  final FileNode node;

  const GenericFileViewerPage({super.key, required this.node});

  @override
  State<GenericFileViewerPage> createState() => _GenericFileViewerPageState();
}

class _GenericFileViewerPageState extends State<GenericFileViewerPage> {
  bool _downloading = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    if (opensStraightInSystemViewer(
      fileKindForName(widget.node.name),
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleOpenWith());
    }
  }

  String get _extension {
    final name = widget.node.name;
    final idx = name.lastIndexOf('.');
    if (idx < 0 || idx == name.length - 1) return '';
    return name.substring(idx).toLowerCase();
  }

  String get _typeLabel {
    if (_extension.isEmpty) return 'Unknown file';
    return '${_extension.substring(1).toUpperCase()} file';
  }

  Future<void> _handleDownload() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      await FilesService.saveFile(
        widget.node.apiPath,
        serial: widget.node.deviceSerial.isEmpty
            ? null
            : widget.node.deviceSerial,
        fileName: widget.node.name,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Downloaded ${widget.node.name}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'download the file'))),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _handleOpenWith() async {
    if (_opening || kIsWeb) return;
    setState(() => _opening = true);
    try {
      final bytes = await FilesService.downloadFileBytes(
        widget.node.apiPath,
        serial: widget.node.deviceSerial.isEmpty
            ? null
            : widget.node.deviceSerial,
      );
      if (bytes == null) throw Exception('Download returned no data');
      final message = await native_open.openFileWithSystem(
        bytes,
        widget.node.name,
      );
      if (message.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(Errors.message(e, 'open the file'))),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.node.name),
        actions: const [AppThemeToggle()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              QuarkFileIcon(
                name: widget.node.name,
                isDir: widget.node.isDir,
                size: 80,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 24),
              Text(
                widget.node.name,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.node.size > 0
                    ? '$_typeLabel  ·  ${_formatSize(widget.node.size)}'
                    : _typeLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 32),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed: _downloading ? null : _handleDownload,
                    icon: _downloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                  if (!kIsWeb)
                    OutlinedButton.icon(
                      onPressed: _opening ? null : _handleOpenWith,
                      icon: _opening
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.open_in_new),
                      label: const Text('Open with…'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
