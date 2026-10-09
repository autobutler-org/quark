import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The fallback viewer for a file Quark has no dedicated viewer for: its details, with download and
/// open-with-another-app actions.
class GenericFileViewerPage extends StatefulWidget {
  final FileNode node;

  /// Closes the viewer from its back button. Null leaves the app bar's own,
  /// which pops the route this viewer was pushed on.
  final VoidCallback? onClose;

  const GenericFileViewerPage({super.key, required this.node, this.onClose});

  @override
  State<GenericFileViewerPage> createState() => _GenericFileViewerPageState();
}

class _GenericFileViewerPageState extends State<GenericFileViewerPage> {
  bool _downloading = false;
  bool _opening = false;

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

  String? get _serial =>
      widget.node.deviceSerial.isEmpty ? null : widget.node.deviceSerial;

  Future<void> _handleDownload() async {
    setState(() => _downloading = true);
    await downloadViewedFile(
      context,
      path: widget.node.apiPath,
      serial: _serial,
      name: widget.node.name,
    );
    if (mounted) setState(() => _downloading = false);
  }

  Future<void> _handleOpenWith() async {
    setState(() => _opening = true);
    await openViewedFileWithSystem(
      context,
      path: widget.node.apiPath,
      serial: _serial,
      name: widget.node.name,
    );
    if (mounted) setState(() => _opening = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: ChromeAppBar(
        leading: widget.onClose == null
            ? null
            : BackButton(onPressed: widget.onClose),
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
                        ? const QuarkLoader(size: 18)
                        : const Icon(Icons.download),
                    label: const Text('Download'),
                  ),
                  if (!kIsWeb)
                    OutlinedButton.icon(
                      onPressed: _opening ? null : _handleOpenWith,
                      icon: _opening
                          ? const QuarkLoader(size: 18)
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
