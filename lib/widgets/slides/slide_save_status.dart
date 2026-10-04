import 'package:flutter/material.dart';
import 'package:quark/controllers/slide_editor_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The slide editor's save state as a bar chip: "Saved", "Save" while edits
/// wait for the autosave, "Saving…" while one is in flight, and "Retry save"
/// after one failed. Tapping it saves now; it is disabled while there is
/// nothing to save or a save is running.
///
/// Key prefixes: `slide_editor_save` on the chip.
class SlideSaveStatus extends StatelessWidget {
  /// Shows [state]; [onSave] saves now.
  const SlideSaveStatus({required this.state, required this.onSave, super.key});

  /// Where the presentation stands against the file on the Quark.
  final SlideSaveState state;

  /// Called when the chip is tapped to save.
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final (icon, label, tooltip) = switch (state) {
      SlideSaveState.saved => (
        QuarkIcons.cloud_done_outlined,
        'Saved',
        'All changes saved',
      ),
      SlideSaveState.dirty => (QuarkIcons.save_outlined, 'Save', 'Save now'),
      SlideSaveState.saving => (
        QuarkIcons.cloud_sync_outlined,
        'Saving…',
        'Saving',
      ),
      SlideSaveState.failed => (
        QuarkIcons.cloud_off_outlined,
        'Retry save',
        Errors.couldNot('save the presentation'),
      ),
    };
    final canSave =
        state == SlideSaveState.dirty || state == SlideSaveState.failed;
    return QuarkBarChip(
      key: const ValueKey('slide_editor_save'),
      icon: icon,
      label: label,
      tooltip: tooltip,
      onPressed: canSave ? onSave : null,
    );
  }
}
