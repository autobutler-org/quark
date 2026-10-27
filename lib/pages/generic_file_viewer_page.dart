import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quark/controllers/document_properties_controller.dart';
import 'package:quark/services/previews_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/widgets/layout/chrome_app_bar.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/file_viewer_actions.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The fallback viewer for a file Quark has no dedicated viewer for: its
/// details, with download and open-with-another-app actions.
///
/// An office file the properties endpoint can read also shows those
/// properties — title, author, and the counts its authoring application
/// last saved (#3275).
class GenericFileViewerPage extends StatefulWidget {
  final FileNode node;

  /// Closes the viewer from its back button. Null leaves the app bar's own,
  /// which pops the route this viewer was pushed on.
  final VoidCallback? onClose;

  /// The properties load for an office file. A test passes one with a fake
  /// read. Null builds the real one, and only when [node] is a format the
  /// properties endpoint reads.
  final DocumentPropertiesController? propertiesController;

  const GenericFileViewerPage({
    super.key,
    required this.node,
    this.onClose,
    this.propertiesController,
  });

  @override
  State<GenericFileViewerPage> createState() => _GenericFileViewerPageState();
}

class _GenericFileViewerPageState extends State<GenericFileViewerPage> {
  bool _downloading = false;
  bool _opening = false;
  DocumentPropertiesController? _properties;
  bool _ownsProperties = false;

  @override
  void initState() {
    super.initState();
    if (!PreviewsService.supportsProperties(widget.node.name)) return;
    final injected = widget.propertiesController;
    if (injected != null) {
      _properties = injected;
    } else {
      _properties = DocumentPropertiesController(
        path: widget.node.apiPath,
        serial: _serial,
      );
      _ownsProperties = true;
    }
    _properties!.load();
  }

  @override
  void dispose() {
    if (_ownsProperties) _properties?.dispose();
    super.dispose();
  }

  String get _typeLabel {
    final extension = fileExtension(widget.node.name);
    // `report.` has a dot and no extension.
    if (extension.length < 2) return 'Unknown file';
    return '${extension.substring(1).toUpperCase()} file';
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
    final properties = _properties;

    return Scaffold(
      appBar: ChromeAppBar(
        leading: widget.onClose == null
            ? null
            : BackButton(onPressed: widget.onClose),
        title: Text(widget.node.name),
        actions: const [AppThemeToggle()],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    QuarkFileIcon(
                      kind: fileIconKindForName(
                        widget.node.name,
                        isDir: widget.node.isDir,
                      ),
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
                          ? '$_typeLabel  ·  ${StorageDevice.formatBytes(widget.node.size)}'
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
                    if (properties != null) ...[
                      const SizedBox(height: 32),
                      ListenableBuilder(
                        listenable: properties,
                        builder: (context, _) => QuarkDocumentProperties(
                          properties: properties.properties,
                          isLoading: properties.isLoading,
                          error: properties.error == null
                              ? null
                              : Errors.message(
                                  properties.error,
                                  'load the properties',
                                ),
                          onRetry: properties.load,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
