import 'package:material_ui/material_ui.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/backup_run_label.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks an admin to restore something from this snapshot-backup drive, says
/// what the restore does in [paragraphs], and asks them to enter their own
/// login password again. `RestoreVaultDialog` and `RestoreChatDialog` are its
/// two uses.
///
/// Names the backup it restores, the newest of [runs] unless another is
/// picked (#4032). Pops with that password and the picked run, null when
/// [runs] is empty, or with nothing on Cancel. An empty password does not
/// confirm. The dialog owns its text controller, so it lives until the route
/// has finished animating out (#3102).
///
/// Keys: `<keyPrefix>_password`, `<keyPrefix>_cancel` and
/// `<keyPrefix>_confirm`.
class RestoreBackupDialog extends StatefulWidget {
  /// Creates the dialog. [runs] are the drive's backups, newest first.
  const RestoreBackupDialog({
    required this.title,
    required this.paragraphs,
    required this.keyPrefix,
    this.runs = const [],
    super.key,
  });

  /// The dialog's title, which names what is restored.
  final String title;

  /// What the restore does, one paragraph each, above the password.
  final List<String> paragraphs;

  /// The prefix of the password field's and the buttons' keys.
  final String keyPrefix;

  /// The backups the restore can read, newest first.
  final List<BackupRun> runs;

  @override
  State<RestoreBackupDialog> createState() => _RestoreBackupDialogState();
}

class _RestoreBackupDialogState extends State<RestoreBackupDialog> {
  final _password = TextEditingController();
  late String? _run = widget.runs.firstOrNull?.folder;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  void _confirm() {
    final password = _password.text;
    if (password.isEmpty) return;
    Navigator.pop(context, (password: password, run: _run));
  }

  @override
  Widget build(BuildContext context) {
    return QuarkWidget.alertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_run case final run?) ...[
            BackupRunPicker(
              runs: [for (final r in widget.runs) backupRunItem(r)],
              selected: run,
              onSelected: (picked) => setState(() => _run = picked),
            ),
            const SizedBox(height: 12),
          ],
          for (final paragraph in widget.paragraphs) ...[
            Text(paragraph),
            const SizedBox(height: 12),
          ],
          TextField(
            key: ValueKey('${widget.keyPrefix}_password'),
            controller: _password,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Your login password',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _confirm(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: ValueKey('${widget.keyPrefix}_cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: ValueKey('${widget.keyPrefix}_confirm'),
          onPressed: _password.text.isEmpty ? null : _confirm,
          child: const Text('Restore'),
        ),
      ],
    );
  }
}
