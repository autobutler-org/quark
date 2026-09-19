import 'package:flutter/material.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/widgets/settings/reset_quark_warning.dart';

/// The aspects of an appliance a reset can wipe, as chosen in the dialog.
@immutable
class QuarkResetSelection {
  /// Creates a selection. The defaults are the dialog's own: everything on
  /// the appliance, and nothing on a drive that merely happens to be plugged
  /// in.
  const QuarkResetSelection({
    this.database = true,
    this.files = true,
    this.devices = false,
  });

  /// Whether to drop and re-migrate the Quark's databases. Takes the accounts
  /// with it, which is why a reset never selects `account` separately.
  final bool database;

  /// Whether to erase the stored file tree.
  final bool files;

  /// Whether to reach the Quark data directory on attached external drives.
  final bool devices;

  /// Whether the Quark would have anything to do. The endpoint rejects a
  /// request that selects nothing, and so does the dialog's button.
  bool get isEmpty => !database && !files && !devices;

  /// Whether this selection leaves data on the appliance behind.
  ///
  /// Files are the ones a person can still open, so they are what the warning
  /// is about; a database left standing keeps the accounts and the metadata
  /// that point at them.
  bool get leavesDataBehind => !database || !files;

  /// What this selection erases, as a phrase that reads after "Erases: ".
  ///
  /// Never empty: the button is disabled on an empty selection, but the line
  /// is on screen while the user is still turning boxes off, and "Erases: "
  /// followed by nothing is a worse answer than saying so.
  String get erasesSummary {
    final parts = [
      if (database) 'accounts and settings',
      if (files) 'stored files',
      if (devices) 'Quark data on attached drives',
    ];
    return parts.isEmpty ? 'nothing yet' : _list(parts);
  }

  /// What this selection leaves alone, as a phrase that reads after "Keeps: ".
  ///
  /// The last entry is unconditional and is the one people are really asking
  /// about: a reset never touches the rest of a drive it was pointed at, and
  /// a drive that is unplugged is not reached at all.
  String get keepsSummary => _list([
    if (!database) 'accounts and settings',
    if (!files) 'stored files',
    if (!devices) 'everything on attached drives',
    if (devices) 'everything else on those drives',
  ]);

  /// Joins [parts] the way a sentence does, with a comma and an "and".
  static String _list(List<String> parts) => switch (parts.length) {
    0 => '',
    1 => parts.first,
    2 => '${parts.first} and ${parts.last}',
    _ => '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}',
  };

  /// A copy of this selection with the named aspects changed.
  QuarkResetSelection copyWith({bool? database, bool? files, bool? devices}) =>
      QuarkResetSelection(
        database: database ?? this.database,
        files: files ?? this.files,
        devices: devices ?? this.devices,
      );
}

/// What the user reads when a reset would leave data on the appliance.
const String kResetQuarkPartialWarning =
    'This leaves data on the Quark. Whoever sets it up next will be able to '
    'reach whatever you leave.';

/// What the user reads when a reset would reach off the appliance and onto a
/// drive they plugged in (#2052).
///
/// Louder than [kResetQuarkPartialWarning] because it is the one choice here
/// that touches something the Quark does not own. Leaving data behind is
/// recoverable by whoever sets the Quark up next; erasing a drive is not
/// recoverable by anyone.
const String kResetQuarkDriveWarning =
    'This erases the Quark data directory on the drives attached right now. '
    'That is the one part of this reset nothing can bring back — not even a '
    'backup drive, if the backup is on it.';

/// The confirmation body for factory-resetting the appliance (#1762).
///
/// Deliberately not the account-deletion dialog. Deleting an account removes a
/// person from a Quark; this empties the Quark itself, and a person who wanted
/// the first must never be able to reach the second by checking something. They
/// are separate entries, separate words, and separate calls.
///
/// Everything on the appliance is selected by default, because leaving nothing
/// behind is what a person coming here wants. External drives are not: a drive
/// plugged in for unrelated reasons must not be wiped because a form arrived
/// with the box already checked, so reaching one is always a deliberate act.
///
/// Each warning appears only once it has something to say: one when the user
/// has turned something off and left data behind, one when they have reached
/// onto an attached drive. A notice that is always on is a notice nobody
/// reads. The scope line below the boxes is the exception — it is always on,
/// because "what will this actually erase" is the question the dialog exists
/// to answer, and it reads back both halves, kept as well as erased (#2052).
///
/// Key prefixes: `reset_quark_database`, `reset_quark_files`,
/// `reset_quark_devices`, `reset_quark_scope`, `reset_quark_warning`,
/// `reset_quark_devices_warning`, `reset_quark_confirm_field`,
/// `reset_quark_cancel`, and `reset_quark_submit`.
///
/// ```dart
/// QuarkWidget.showDialog<(QuarkResetSelection, String)>(
///   context,
///   builder: (ctx) => ResetQuarkDialog(
///     username: AppSettings.instance.username,
///     onConfirm: (selection, confirm) =>
///         Navigator.of(ctx).pop((selection, confirm)),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class ResetQuarkDialog extends StatefulWidget {
  /// Creates the reset confirmation for the Quark [username] is signed in to.
  const ResetQuarkDialog({
    required this.onConfirm,
    required this.onCancel,
    this.username,
    super.key,
  });

  /// The signed-in account, or null when this session never named one. Only
  /// used to check and phrase the confirmation.
  final String? username;

  /// Called with the chosen aspects and the typed confirmation, once the
  /// confirmation matches and at least one aspect is selected.
  final void Function(QuarkResetSelection selection, String confirmUsername)
  onConfirm;

  /// Called when the user backs out through the cancel button.
  final VoidCallback onCancel;

  @override
  State<ResetQuarkDialog> createState() => _ResetQuarkDialogState();
}

class _ResetQuarkDialogState extends State<ResetQuarkDialog> {
  final _confirmController = TextEditingController();
  QuarkResetSelection _selection = const QuarkResetSelection();

  @override
  void dispose() {
    _confirmController.dispose();
    super.dispose();
  }

  bool get _isConfirmed {
    final typed = _confirmController.text.trim();
    final expected = widget.username;
    return expected == null ? typed.isNotEmpty : typed == expected;
  }

  void _submit() {
    if (!_isConfirmed || _selection.isEmpty) return;
    widget.onConfirm(_selection, _confirmController.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final username = widget.username;

    return QuarkWidget.alertDialog(
      title: const Text('Reset this Quark'),
      scrollable: true,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Returns this Quark to first-boot setup. Every account on it goes, '
            'yours included, and it has to be set up again. This cannot be '
            'undone.',
          ),
          const SizedBox(height: 12),
          CheckboxListTile(
            key: const ValueKey('reset_quark_database'),
            value: _selection.database,
            onChanged: (value) => setState(
              () => _selection = _selection.copyWith(database: value ?? false),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Accounts and settings'),
            subtitle: const Text(
              'Every account, album, calendar, and setting on this Quark.',
            ),
          ),
          CheckboxListTile(
            key: const ValueKey('reset_quark_files'),
            value: _selection.files,
            onChanged: (value) => setState(
              () => _selection = _selection.copyWith(files: value ?? false),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Stored files'),
            subtitle: const Text(
              'Every photo and document stored on the Quark itself.',
            ),
          ),
          CheckboxListTile(
            key: const ValueKey('reset_quark_devices'),
            value: _selection.devices,
            onChanged: (value) => setState(
              () => _selection = _selection.copyWith(devices: value ?? false),
            ),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Quark data on attached drives'),
            subtitle: const Text(
              'Off by default. Only the Quark data directory on drives '
              'attached right now; anything else on them is left alone.',
            ),
          ),
          const SizedBox(height: 12),
          // Reads back the boxes above as two plain sentences. The checkboxes
          // say what each one does; this says what the reset as a whole comes
          // to, which is the question someone hovering over the button is
          // actually asking (#2052).
          Text(
            key: const ValueKey('reset_quark_scope'),
            'Erases: ${_selection.erasesSummary}\n'
            'Keeps: ${_selection.keepsSummary}',
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (_selection.leavesDataBehind) ...[
            const SizedBox(height: 8),
            const ResetQuarkWarning(
              key: ValueKey('reset_quark_warning'),
              message: kResetQuarkPartialWarning,
            ),
          ],
          if (_selection.devices) ...[
            const SizedBox(height: 8),
            const ResetQuarkWarning(
              key: ValueKey('reset_quark_devices_warning'),
              message: kResetQuarkDriveWarning,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            username == null
                ? 'Type your username to confirm.'
                : 'Type $username to confirm.',
          ),
          const SizedBox(height: 8),
          QuarkWidget.textField(
            key: const ValueKey('reset_quark_confirm_field'),
            controller: _confirmController,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            hintText: username ?? 'username',
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('reset_quark_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('reset_quark_submit'),
          style: FilledButton.styleFrom(
            backgroundColor: colorScheme.error,
            foregroundColor: colorScheme.onError,
          ),
          onPressed: _isConfirmed && !_selection.isEmpty ? _submit : null,
          child: const Text('Reset this Quark'),
        ),
      ],
    );
  }
}
