import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:quark/controllers/file_versions_controller.dart';
import 'package:quark/pages/image_viewer_page.dart';
import 'package:quark/pages/svg_viewer_page.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/auto_refresh_mixin.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/widgets/file_browser/archive_text_preview.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the version history of the file at [relPath] on the internal drive,
/// titled with its [name] (#2992).
Future<void> showFileVersionsSheet(
  BuildContext context, {
  required String relPath,
  required String name,
}) => showQuarkSheet<void>(
  context,
  title: 'Version history · $name',
  builder: (_) => FileVersionsSheet(relPath: relPath, name: name),
);

/// The body of the version history sheet: a [FileVersionsPanel] around a
/// [FileVersionsController] that lives as long as the sheet is open.
///
/// Restore asks first with a [ConfirmDeleteDialog], then reloads the list.
/// What a restore or a preview comes to is said in the sheet, where a snack
/// bar would be hidden under it.
///
/// Preview opens a version's bytes in a read-only viewer with no path behind
/// it, so nothing it offers can save over the live file: images Flutter
/// decodes itself, SVG, and text, code and CSV as plain text. Any other kind,
/// and a version over [maxPreviewBytes], says a preview is not available.
class FileVersionsSheet extends StatefulWidget {
  const FileVersionsSheet({
    required this.relPath,
    required this.name,
    this.controller,
    super.key,
  });

  /// The largest version a preview downloads: it is held in memory whole.
  static const int maxPreviewBytes = 25 * 1024 * 1024;

  /// What the sheet says for a version it has no read-only viewer for.
  static const String previewUnavailable =
      "A preview isn't available for this kind of file.";

  /// What the sheet says for a version over [maxPreviewBytes].
  static const String previewTooLarge = 'This version is too large to preview.';

  /// What the sheet says once a restore has landed.
  static const String restored =
      'Restored. What the file held is saved as "Before restore".';

  /// The file's files-relative path on the internal drive.
  final String relPath;

  /// The file's name, which also decides how a version previews.
  final String name;

  /// The controller to use and dispose, for a test; null builds the real one.
  final FileVersionsController? controller;

  @override
  State<FileVersionsSheet> createState() => _FileVersionsSheetState();
}

class _FileVersionsSheetState extends State<FileVersionsSheet>
    with WidgetsBindingObserver, AutoRefreshMixin {
  late final FileVersionsController _controller =
      widget.controller ??
      FileVersionsController(
        path: widget.relPath,
        selfUserId: AppSettings.instance.userId.value,
      );
  String? _error;
  String? _notice;

  @override
  Future<void> refresh() => _controller.load();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _say({String? error, String? notice}) => setState(() {
    _error = error;
    _notice = notice;
  });

  Future<void> _restore(String id) async {
    final version = _controller.versionFor(id);
    if (version == null) return;
    final confirmed = await confirmDestructive(
      context,
      title: 'Restore this version?',
      body:
          '${widget.name} goes back to the version from '
          '${formatVersionTime(context, version.createdAt)}. What it '
          'holds now is saved first as "Before restore", so you can undo '
          'this.',
      keyPrefix: 'file_version_restore',
      confirmLabel: 'Restore',
      destructive: false,
    );
    if (!confirmed || !mounted) return;
    _say();
    final error = await _controller.restore(id);
    if (!mounted) return;
    _say(
      error: error == null
          ? null
          : Errors.message(error, 'restore that version'),
      notice: error == null ? FileVersionsSheet.restored : null,
    );
  }

  Future<void> _preview(String id) async {
    final version = _controller.versionFor(id);
    if (version == null) return;
    final name = widget.name;
    final kind = fileKindForName(name);
    final hasViewer = switch (kind) {
      FileKind.image => clientDecodedImageExtensions.contains(
        fileExtension(name),
      ),
      FileKind.svg || FileKind.text || FileKind.code || FileKind.csv => true,
      _ => false,
    };
    if (!hasViewer || version.size > FileVersionsSheet.maxPreviewBytes) {
      _say(
        error: hasViewer
            ? FileVersionsSheet.previewTooLarge
            : FileVersionsSheet.previewUnavailable,
      );
      return;
    }
    _say();
    try {
      final bytes = await _controller.content(id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => switch (kind) {
            FileKind.image => ImageViewerPage(bytes: bytes, name: name),
            FileKind.svg => SvgViewerPage(bytes: bytes, name: name),
            _ => ArchiveTextPreview(
              name: name,
              text: utf8.decode(bytes, allowMalformed: true),
            ),
          },
        ),
      );
    } catch (e) {
      if (mounted) _say(error: Errors.message(e, 'load that version'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final loadError = _controller.error;
        return FileVersionsPanel(
          versions: _controller.items,
          isLoading: isInitialLoad,
          error:
              _error ??
              (loadError == null
                  ? null
                  : Errors.message(loadError, 'load the version history')),
          notice: _notice,
          busyId: _controller.busyId,
          onPreview: _preview,
          onRestore: _restore,
          onRefresh: manualRefresh,
          isRefreshing: isRefreshing,
        );
      },
    );
  }
}
