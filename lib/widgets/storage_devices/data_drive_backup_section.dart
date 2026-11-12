import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/data_protection_controller.dart';
import 'package:quark/services/data_protection_service.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// A data drive's backup chip on its drive card: "Not backed up", "Backed up
/// Nov 2 · Backup A", or "Protected · Nov 2", opening to one line per backup
/// drive's copy with the Quark's reason when that copy does not count.
///
/// The wording is built here from [drive]; expansion stays here too.
class DataDriveBackupSection extends StatefulWidget {
  /// Creates the chip for [drive], keyed with [id].
  const DataDriveBackupSection({
    required this.drive,
    required this.id,
    super.key,
  });

  /// The drive's level and copies as the Quark reported them.
  final DataProtectionDataDrive drive;

  /// Distinguishes this drive's keys from the others on the page.
  final String id;

  @override
  State<DataDriveBackupSection> createState() => _DataDriveBackupSectionState();
}

class _DataDriveBackupSectionState extends State<DataDriveBackupSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    String day(DateTime at) => localizations.formatShortMonthDay(at.toLocal());

    final drive = widget.drive;
    final level =
        DataProtectionController.levelOf(drive.level) ??
        DataProtectionLevel.unprotected;
    // Copies are newest first, so the first counting one is the newest.
    final newest = drive.copies.where((c) => c.counts).firstOrNull;
    final label = switch ((level, newest)) {
      (DataProtectionLevel.protected, final c?) =>
        'Protected · ${day(c.copiedAt)}',
      (DataProtectionLevel.unprotected, _) || (_, null) => 'Not backed up',
      (_, final c?) => 'Backed up ${day(c.copiedAt)} · ${c.backupName}',
    };

    return DriveBackupChip(
      id: widget.id,
      level: level,
      label: label,
      copies: [
        for (final copy in drive.copies)
          [
            copy.backupName,
            day(copy.copiedAt),
            if (!copy.counts) ?copy.reason,
          ].join(' · '),
      ],
      expanded: _expanded,
      onExpandedChanged: (open) => setState(() => _expanded = open),
    );
  }
}
