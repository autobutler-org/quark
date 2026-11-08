import 'package:quark/services/storage_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the app calls a backup run, from the folder the Quark names it by:
/// "2026-11-02 09.00" is "Nov 2, 09.00", and "2026-11-02 09.00 (2)", the
/// second run started that minute, is "Nov 2, 09.00 (2)". The folder is the
/// Quark's local time, so the label is too. A folder in any other shape is
/// shown as it is.
String backupRunLabel(String folder) {
  final match = _runFolder.firstMatch(folder);
  if (match == null) return folder;
  final month = int.parse(match[2]!);
  if (month < 1 || month > 12) return folder;
  return '${_months[month - 1]} ${int.parse(match[3]!)}, ${match[4]}${match[5]}';
}

final _runFolder = RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}\.\d{2})(.*)$');

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// [run] in the words the package's run widgets show: its [backupRunLabel],
/// its size, and the names of the drives it holds.
BackupRunItem backupRunItem(BackupRun run) => BackupRunItem(
  id: run.folder,
  time: backupRunLabel(run.folder),
  size: StorageDevice.formatBytes(run.sizeBytes),
  drives: run.drives.map((d) => d.name.isEmpty ? d.folder : d.name).join(', '),
);
