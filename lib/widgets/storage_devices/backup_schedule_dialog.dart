import 'package:material_ui/material_ui.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/storage_devices/backup_source_list.dart';

/// Asks how often the Quark backs up onto the backup drive named
/// [targetName] on its own, and which of the data drives in [sources] it
/// copies (#3984). It opens on [cadence] and [sourceSerials], every drive
/// checked when that is empty. Save is off while no drive is checked.
///
/// Pops with the cadence and the checked serials on Save, or with nothing on
/// Cancel. Every drive checked pops an empty list, which the Quark reads as
/// every data drive, one plugged in later included.
///
/// Each cadence is keyed `backup_schedule_cadence_<name>` (`off`, `daily`,
/// `weekly`, `monthly`), each drive's checkbox is a [BackupSourceList] key,
/// `backup_source_<serial>`, and Save is `backup_schedule_save`.
class BackupScheduleDialog extends StatefulWidget {
  /// Creates the dialog over [sources], serial to name, in display order.
  const BackupScheduleDialog({
    required this.targetName,
    required this.sources,
    this.cadence = BackupCadence.off,
    this.sourceSerials = const [],
    super.key,
  });

  /// The backup drive's name; empty reads as "this drive".
  final String targetName;

  /// The data drives the schedule can copy, serial to name.
  final Map<String, String> sources;

  /// The cadence the drive has now.
  final BackupCadence cadence;

  /// The drives the schedule copies now; empty is every one.
  final List<String> sourceSerials;

  @override
  State<BackupScheduleDialog> createState() => _BackupScheduleDialogState();
}

class _BackupScheduleDialogState extends State<BackupScheduleDialog> {
  late BackupCadence _cadence = widget.cadence;
  late final Set<String> _checked = widget.sourceSerials.isEmpty
      ? widget.sources.keys.toSet()
      : widget.sourceSerials.where(widget.sources.containsKey).toSet();

  static const _labels = {
    BackupCadence.off: 'Off',
    BackupCadence.daily: 'Daily',
    BackupCadence.weekly: 'Weekly',
    BackupCadence.monthly: 'Monthly',
  };

  @override
  Widget build(BuildContext context) {
    final target = widget.targetName.isNotEmpty
        ? widget.targetName
        : 'this drive';
    return QuarkWidget.alertDialog(
      title: const Text('Back up on a schedule'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('How often to back up onto $target while it is plugged in.'),
          RadioGroup<BackupCadence>(
            groupValue: _cadence,
            onChanged: (value) {
              if (value != null) setState(() => _cadence = value);
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final cadence in BackupCadence.values)
                  RadioListTile<BackupCadence>(
                    key: ValueKey('backup_schedule_cadence_${cadence.name}'),
                    contentPadding: EdgeInsets.zero,
                    value: cadence,
                    title: Text(_labels[cadence]!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Choose the drives to copy.'),
          BackupSourceList(
            sources: widget.sources,
            checked: _checked,
            onChanged: (serial, checked) => setState(
              () => checked ? _checked.add(serial) : _checked.remove(serial),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('backup_schedule_save'),
          onPressed: _checked.isEmpty
              ? null
              : () => Navigator.pop(context, (
                  cadence: _cadence,
                  sourceSerials: _checked.length == widget.sources.length
                      ? const <String>[]
                      : [
                          for (final serial in widget.sources.keys)
                            if (_checked.contains(serial)) serial,
                        ],
                )),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
