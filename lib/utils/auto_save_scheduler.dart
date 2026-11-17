import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';

/// Runs an editor's auto-save [delay] after its last edit, and holds it while
/// the editor asks whether to leave with unsaved changes (#4110).
///
/// The editor calls [schedule] on every edit and [track] around every save,
/// the upload and the clearing of its unsaved mark together.
/// [confirmLeave] cancels the countdown, waits for an upload already in
/// flight, and keeps a new countdown from starting while the prompt is open,
/// so the answer is about the edit as it stands rather than one that saves
/// itself behind the dialog.
class AutoSaveScheduler {
  AutoSaveScheduler({required this.delay, required this.onFire});

  /// How long after the last edit the save runs.
  final Duration delay;

  /// The save, run when the countdown ends.
  final VoidCallback onFire;

  Timer? _timer;
  final Set<Future<void>> _inFlight = {};
  bool _held = false;

  /// Whether a leave prompt is holding auto-save.
  bool get isHeld => _held;

  /// Restarts the countdown. Does nothing while [isHeld].
  void schedule() {
    cancel();
    if (_held) return;
    _timer = Timer(delay, onFire);
  }

  /// Stops the countdown without saving.
  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  /// Records [save] as in flight, so [confirmLeave] waits for it, and
  /// returns it.
  Future<T> track<T>(Future<T> save) {
    late final Future<void> settled;
    settled = save.then<void>(
      (_) => _inFlight.remove(settled),
      onError: (_) => _inFlight.remove(settled),
    );
    _inFlight.add(settled);
    return save;
  }

  /// Whether the editor may leave: true at once when [isDirty] is false once
  /// any upload in flight has landed, and otherwise whatever [ask] answers.
  ///
  /// Auto-save is held until the answer comes back. When the answer is to
  /// stay and the edit is still unsaved, the countdown restarts if [resume]
  /// is true, so the edit is saved after all.
  Future<bool> confirmLeave({
    required bool Function() isDirty,
    required Future<bool> Function() ask,
    bool resume = true,
  }) async {
    cancel();
    _held = true;
    final bool leave;
    try {
      await Future.wait(_inFlight.toList());
      leave = !isDirty() || await ask();
    } finally {
      _held = false;
    }
    if (!leave && resume && isDirty()) schedule();
    return leave;
  }

  /// Stops the countdown for good.
  void dispose() => cancel();
}

/// Asks "Leave without saving?", the question every editor with unsaved
/// changes asks before it closes. True means leave.
Future<bool> confirmLeaveUnsaved(BuildContext context) async =>
    await confirmAction(
      context,
      title: 'Unsaved changes',
      message: 'You have unsaved changes. Leave without saving?',
      confirmLabel: 'Leave',
    ) ??
    false;
