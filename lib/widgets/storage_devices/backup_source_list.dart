import 'package:material_ui/material_ui.dart';

/// One checkbox per data drive a backup can copy (#3984), shared by the
/// backup and schedule dialogs. The dialog owns which are [checked] and
/// changes them in [onChanged].
///
/// Each checkbox is keyed `backup_source_<serial>`; built-in storage is the
/// serial "", so its key is `backup_source_`.
class BackupSourceList extends StatelessWidget {
  /// Creates the list over [sources], serial to name, in display order.
  const BackupSourceList({
    required this.sources,
    required this.checked,
    required this.onChanged,
    super.key,
  });

  /// The data drives, serial to name.
  final Map<String, String> sources;

  /// The serials whose box is checked.
  final Set<String> checked;

  /// Called with a drive's serial and whether its box is now checked.
  final void Function(String serial, bool checked) onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final MapEntry(key: serial, value: name) in sources.entries)
          CheckboxListTile(
            key: ValueKey('backup_source_$serial'),
            contentPadding: EdgeInsets.zero,
            value: checked.contains(serial),
            onChanged: (value) => onChanged(serial, value == true),
            title: Text(name),
          ),
      ],
    );
  }
}
