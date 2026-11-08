import 'package:flutter/foundation.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/backup_run_label.dart';

/// Restores every account's vault from a snapshot-backup drive (#3664).
///
/// [restore] asks the Quark and keeps the outcome: [result] on success,
/// [error] when the restore was refused. [summary] is the sentence the Storage
/// tab shows for a success, including who must unlock with the password they
/// had when the backup was taken. The page does not build that sentence itself.
class RestoreVaultController extends ChangeNotifier {
  /// Builds a controller. [restoreVault] defaults to
  /// [StorageService.restoreSnapshotVault].
  RestoreVaultController({
    Future<VaultRestoreResult> Function({
      required String deviceSerial,
      required String password,
      String? run,
    })?
    restoreVault,
  }) : _restoreVault = restoreVault ?? StorageService.restoreSnapshotVault;

  final Future<VaultRestoreResult> Function({
    required String deviceSerial,
    required String password,
    String? run,
  })
  _restoreVault;

  VaultRestoreResult? _result;
  Object? _error;

  /// The last successful restore, or null after a failure or before the first.
  VaultRestoreResult? get result => _result;

  /// The thrown object from the last failed [restore]. A success clears it.
  Object? get error => _error;

  /// The sentence for [result], or null when there is none.
  String? get summary {
    final result = _result;
    return result == null ? null : restoreVaultSummary(result);
  }

  /// Restores the vaults on [deviceSerial] from the backup [run], or the
  /// newest one when [run] is null. [password] is the admin's login
  /// password. Success sets [result] and clears [error]; a throw does the
  /// opposite.
  Future<void> restore({
    required String deviceSerial,
    required String password,
    String? run,
  }) async {
    try {
      _result = await _restoreVault(
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

/// The sentence for [result]: how many vaults and entries came
/// back and from which backup, and, when [VaultRestoreResult.backupPasswordAccounts] is not empty,
/// who unlocks with the password they had when the backup was taken.
String restoreVaultSummary(VaultRestoreResult result) {
  final accounts = result.accounts == 1
      ? '1 vault'
      : '${result.accounts} vaults';
  final items = result.items == 1 ? '1 entry' : '${result.items} entries';
  final run = result.run;
  final when = run == null ? '' : ', backed up ${backupRunLabel(run)}';
  final summary = 'Restored $accounts and $items$when.';
  final names = result.backupPasswordAccounts;
  if (names.isEmpty) return summary;
  final who = switch (names.length) {
    1 => names.single,
    2 => '${names[0]} and ${names[1]}',
    _ => '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}',
  };
  final verb = names.length == 1 ? 'unlocks' : 'unlock';
  return '$summary $who $verb with the password they had when the backup '
      'was taken.';
}
