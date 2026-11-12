import 'package:flutter/foundation.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/backup_run_label.dart';

/// Restores the chat from a snapshot-backup drive (#2428).
///
/// [restore] asks the Quark and keeps the outcome: [result] on success,
/// [error] when the restore was refused. [summary] is the sentence the Storage
/// tab shows for a success, naming the usernames the backup has that no
/// account here matched. The page does not build that sentence itself.
class RestoreChatController extends ChangeNotifier {
  /// Builds a controller. [restoreChat] defaults to
  /// [StorageService.restoreSnapshotChat].
  RestoreChatController({
    Future<ChatRestoreResult> Function({
      required String deviceSerial,
      required String password,
      String? run,
    })?
    restoreChat,
  }) : _restoreChat = restoreChat ?? StorageService.restoreSnapshotChat;

  final Future<ChatRestoreResult> Function({
    required String deviceSerial,
    required String password,
    String? run,
  })
  _restoreChat;

  ChatRestoreResult? _result;
  Object? _error;

  /// The last successful restore, or null after a failure or before the first.
  ChatRestoreResult? get result => _result;

  /// The thrown object from the last failed [restore]. A success clears it.
  Object? get error => _error;

  /// The sentence for [result], or null when there is none.
  String? get summary {
    final result = _result;
    return result == null ? null : restoreChatSummary(result);
  }

  /// Restores the chat on [deviceSerial] from the backup [run], or the newest
  /// one when [run] is null. [password] is the admin's login password.
  /// Success sets [result] and clears [error]; a throw does the opposite.
  Future<void> restore({
    required String deviceSerial,
    required String password,
    String? run,
  }) async {
    try {
      _result = await _restoreChat(
        deviceSerial: deviceSerial,
        password: password,
        run: run,
      );
      _error = null;
    } catch (e) {
      _error = e;
      _result = null;
    }
    notifyListeners();
  }
}

/// The sentence for [result]: how many channels and messages came back and
/// from which backup, and, when [ChatRestoreResult.unmatchedUsers] is not
/// empty, the usernames no account here matched.
String restoreChatSummary(ChatRestoreResult result) {
  final channels = result.channels == 1
      ? '1 channel'
      : '${result.channels} channels';
  final messages = result.messages == 1
      ? '1 message'
      : '${result.messages} messages';
  final run = result.run;
  final when = run == null ? '' : ', backed up ${backupRunLabel(run)}';
  final summary = 'Restored $channels and $messages$when.';
  final names = result.unmatchedUsers;
  if (names.isEmpty) return summary;
  return '$summary No account here matched these usernames, so their '
      'messages show no author: ${names.join(', ')}.';
}
