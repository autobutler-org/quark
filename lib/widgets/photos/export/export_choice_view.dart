import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/export_photos_controller.dart';
import 'package:quark/widgets/photos/export/export_explanation.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The first step of the export dialog (#3501): what the export does, what
/// to export (the whole library, or albums ticked from the list), and where
/// it goes (a drive, then a folder on it).
///
/// Key prefixes: `export_scope_library` and `export_scope_albums` on the
/// choice, `export_album_<id>` on each album, `export_drive_<serial>` on each
/// drive (`export_drive_internal` for an empty serial),
/// `export_choose_folder` on the folder button, and `export_start_error` on
/// a refusal.
class ExportChoiceView extends StatelessWidget {
  /// Creates the view over [controller].
  const ExportChoiceView({
    required this.controller,
    required this.onChooseFolder,
    super.key,
  });

  /// The export's state.
  final ExportPhotosController controller;

  /// Opens the folder picker on the chosen drive.
  final VoidCallback onChooseFolder;

  /// The key suffix for a drive's [serial].
  static String driveKey(String serial) =>
      'export_drive_${serial.isEmpty ? 'internal' : serial}';

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final theme = Theme.of(context);
    final tokens = QuarkTokens.of(context);
    final heading = theme.textTheme.titleSmall;
    final startError = c.startError;
    final drivesError = c.drivesError;
    final folder = c.folder;
    final drive = c.drive;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const ExportExplanation(),
          const SizedBox(height: 16),
          Text('What to export', style: heading),
          RadioGroup<ExportScope>(
            groupValue: c.scope,
            onChanged: (scope) {
              if (scope != null) c.setScope(scope);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const RadioListTile<ExportScope>(
                  key: ValueKey('export_scope_library'),
                  contentPadding: EdgeInsets.zero,
                  value: ExportScope.library,
                  title: Text('The whole photo library'),
                  subtitle: Text(
                    'Every album, plus the photos in no album, which go in a '
                    'folder called "Not in an album".',
                  ),
                ),
                RadioListTile<ExportScope>(
                  key: const ValueKey('export_scope_albums'),
                  contentPadding: EdgeInsets.zero,
                  value: ExportScope.albums,
                  enabled: c.albums.isNotEmpty,
                  title: const Text('Albums I choose'),
                  subtitle: Text(
                    c.albums.isEmpty
                        ? 'You have no albums yet.'
                        : 'Each album becomes a folder, and its sub-albums '
                              'folders inside it.',
                  ),
                ),
              ],
            ),
          ),
          if (c.scope == ExportScope.albums)
            for (final (album, depth) in c.albums)
              CheckboxListTile(
                key: ValueKey('export_album_${album.id}'),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.only(left: 16.0 + depth * 16),
                value: c.selectedAlbumIds.contains(album.id),
                onChanged: (_) => c.toggleAlbum(album.id),
                title: Text(album.name),
                subtitle: Text(album.photoCountLabel),
              ),
          const SizedBox(height: 16),
          Text('Where it goes', style: heading),
          const SizedBox(height: 4),
          if (c.drivesLoading && c.drives.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8),
              child: QuarkLoader(size: 20),
            )
          else if (drivesError != null)
            Text(drivesError, style: TextStyle(color: tokens.error))
          else
            RadioGroup<String>(
              groupValue: c.serial,
              onChanged: (serial) {
                if (serial != null) c.selectDrive(serial);
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final target in c.drives)
                    RadioListTile<String>(
                      key: ValueKey(driveKey(target.serial)),
                      contentPadding: EdgeInsets.zero,
                      value: target.serial,
                      enabled: target.unavailableReason == null,
                      title: Text(
                        target.name.isNotEmpty ? target.name : 'Drive',
                      ),
                      subtitle: target.unavailableReason == null
                          ? null
                          : Text(target.unavailableReason!),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  folder == null
                      ? 'No folder chosen yet.'
                      : 'Into a new folder inside $folder'
                            '${drive == null ? '' : ' on ${drive.name}'}.',
                  key: const ValueKey('export_folder_label'),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const ValueKey('export_choose_folder'),
                onPressed: c.serial == null ? null : onChooseFolder,
                icon: const Icon(QuarkIcons.folder_open, size: 18),
                label: Text(folder == null ? 'Choose folder' : 'Change'),
              ),
            ],
          ),
          if (startError != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                startError,
                key: const ValueKey('export_start_error'),
                style: TextStyle(color: tokens.error),
              ),
            ),
        ],
      ),
    );
  }
}
