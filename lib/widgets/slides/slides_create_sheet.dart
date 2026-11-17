import 'package:material_ui/material_ui.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the Slides page's + button opens on a phone (#4227): "New
/// presentation" and "Import a PowerPoint file". A phone has no bar row for
/// the import, so it lives here; choosing it asks where the file is, the
/// Quark or this device, as the wide screen's Import chip does.
///
/// Each choice closes its sheet before its callback runs, so the dialog or
/// picker it opens is not stacked on the sheet.
///
/// Key prefixes: `slides_create_new` and `slides_create_import` on the first
/// sheet, and `slides_import_from_quark` and `slides_import_from_device` on
/// the second, the same keys the wide screen's import menu uses.
///
/// ```dart
/// showSlidesCreateSheet(
///   context,
///   onNew: create,
///   onImportFromQuark: pickOnQuark,
///   onImportFromDevice: pickOnDevice,
/// );
/// ```
Future<void> showSlidesCreateSheet(
  BuildContext context, {
  required VoidCallback onNew,
  required VoidCallback onImportFromQuark,
  required VoidCallback onImportFromDevice,
}) async {
  final next = await _choose(context, 'Add a presentation', [
    (key: 'slides_create_new', icon: QuarkIcons.add, label: 'New presentation'),
    (
      key: 'slides_create_import',
      icon: QuarkIcons.import_file,
      label: 'Import a PowerPoint file',
    ),
  ]);
  if (next == 'slides_create_new') onNew();
  if (next != 'slides_create_import' || !context.mounted) return;
  final source = await _choose(context, 'Import a PowerPoint file', [
    (
      key: 'slides_import_from_quark',
      icon: QuarkIcons.folder_open,
      label: 'From your Quark',
    ),
    (
      key: 'slides_import_from_device',
      icon: QuarkIcons.upload_rounded,
      label: 'From this device',
    ),
  ]);
  if (source == 'slides_import_from_quark') onImportFromQuark();
  if (source == 'slides_import_from_device') onImportFromDevice();
}

typedef _Choice = ({String key, IconData icon, String label});

/// Shows [choices] in a sheet called [title] and returns the key of the one
/// tapped, or null when the sheet is dismissed.
Future<String?> _choose(
  BuildContext context,
  String title,
  List<_Choice> choices,
) => showQuarkSheet<String>(
  context,
  title: title,
  builder: (ctx) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final c in choices)
        ListTile(
          key: ValueKey(c.key),
          contentPadding: EdgeInsets.zero,
          leading: Icon(c.icon),
          title: Text(c.label),
          onTap: () => Navigator.of(ctx).pop(c.key),
        ),
    ],
  ),
);
