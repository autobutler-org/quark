import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/export_photos_controller.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/widgets/photos/export/export_choice_view.dart';
import 'package:quark/widgets/photos/export/export_folder_dialog.dart';
import 'package:quark/widgets/photos/export/export_result_view.dart';
import 'package:quark/widgets/photos/export/export_running_view.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Exports albums, or the whole photo library, as copied files and a
/// manifest into a folder the person chooses (#3501).
///
/// It walks [ExportPhotosController]'s phases: choose what and where, then
/// say where the export is going while the Quark copies, then show how it
/// ended, listing by name any photo that was not copied.
///
/// Key prefixes: `export_start` on the Export button, `export_close` on
/// Close and Cancel, `export_open_jobs` on Open Jobs, plus those of
/// [ExportChoiceView], [ExportRunningView] and [ExportResultView].
class ExportPhotosDialog extends StatefulWidget {
  /// Creates the dialog over [controller], which it disposes.
  const ExportPhotosDialog({
    required this.controller,
    this.internalRoot = '',
    this.onOpenJobs,
    super.key,
  });

  /// The export's state.
  final ExportPhotosController controller;

  /// Where the folder picker starts on the internal drive: the top for an
  /// admin, the account's home for anyone else. Other drives start at their
  /// top.
  final String internalRoot;

  /// Opens the Jobs list. Null leaves "Open Jobs" out.
  final VoidCallback? onOpenJobs;

  /// Shows the dialog over [albums], with [initialAlbumIds] ticked, or the
  /// whole library chosen when [library] is true.
  static Future<void> show(
    BuildContext context, {
    required List<AlbumItem> albums,
    Set<int> initialAlbumIds = const {},
    bool library = false,
    VoidCallback? onOpenJobs,
  }) {
    final settings = AppSettings.instance;
    return showDialog<void>(
      context: context,
      builder: (context) => ExportPhotosDialog(
        controller: ExportPhotosController(
          albums: albums,
          initialAlbumIds: initialAlbumIds,
          scope: library ? ExportScope.library : ExportScope.albums,
        ),
        internalRoot: landingPath(
          isAdmin: settings.isAdmin.value,
          username: settings.username,
        ),
        onOpenJobs: onOpenJobs,
      ),
    );
  }

  @override
  State<ExportPhotosDialog> createState() => _ExportPhotosDialogState();
}

class _ExportPhotosDialogState extends State<ExportPhotosDialog> {
  ExportPhotosController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_c.loadDrives());
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String get _driveName {
    final name = _c.drive?.name ?? '';
    return name.isEmpty ? 'the drive' : name;
  }

  Future<void> _chooseFolder() async {
    final serial = _c.serial;
    if (serial == null) return;
    final folder = await ExportFolderDialog.show(
      context,
      driveName: _driveName,
      rootPath: serial.isEmpty ? widget.internalRoot : '',
      listFiles: _c.listFolder,
    );
    if (folder != null) _c.selectFolder(folder);
  }

  void _openJobs() {
    Navigator.of(context).pop();
    widget.onOpenJobs?.call();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final phase = _c.phase;
        final queued = _c.queued;
        final onOpenJobs = widget.onOpenJobs;
        final close = TextButton(
          key: const ValueKey('export_close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(phase == ExportPhase.choosing ? 'Cancel' : 'Close'),
        );
        return AlertDialog(
          title: Text(switch (phase) {
            ExportPhase.choosing => 'Export photos',
            ExportPhase.starting || ExportPhase.running => 'Exporting photos',
            ExportPhase.finished => 'Export result',
          }),
          content: SizedBox(
            width: 480,
            child: switch (phase) {
              ExportPhase.choosing => ExportChoiceView(
                controller: _c,
                onChooseFolder: () => unawaited(_chooseFolder()),
              ),
              ExportPhase.starting || ExportPhase.running => ExportRunningView(
                driveName: _driveName,
                relPath: queued?.relPath ?? _c.folder ?? '',
                progress: _c.progress,
                isStarting: phase == ExportPhase.starting,
              ),
              ExportPhase.finished => ExportResultView(
                driveName: _driveName,
                summary: _c.summary,
                error: _c.summaryError,
              ),
            },
          ),
          actions: [
            if (phase != ExportPhase.choosing && onOpenJobs != null)
              TextButton(
                key: const ValueKey('export_open_jobs'),
                onPressed: _openJobs,
                child: const Text('Open Jobs'),
              ),
            close,
            if (phase == ExportPhase.choosing)
              FilledButton(
                key: const ValueKey('export_start'),
                onPressed: _c.canStart ? () => unawaited(_c.start()) : null,
                child: const Text('Export'),
              ),
          ],
        );
      },
    );
  }
}
