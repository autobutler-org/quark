import 'package:flutter/foundation.dart';
import 'package:quark/services/storage_service.dart';

/// Starts a restore of a snapshot drive's files (#4009).
///
/// [restore] asks the Quark and keeps the outcome: [result] once the restore
/// is queued, [error] when it was refused. [summary] is the sentence the
/// Storage tab shows, naming the drives whose files stay behind.
class RestoreFilesController extends ChangeNotifier {
  /// Builds a controller. [restoreFiles] defaults to
  /// [StorageService.restoreSnapshotFiles].
  RestoreFilesController({
    Future<FilesRestoreResult> Function({
      required String deviceSerial,
      required bool missingToBuiltIn,
    })?
    restoreFiles,
  }) : _restoreFiles = restoreFiles ?? StorageService.restoreSnapshotFiles;

  final Future<FilesRestoreResult> Function({
    required String deviceSerial,
    required bool missingToBuiltIn,
  })
  _restoreFiles;

  FilesRestoreResult? _result;
  Object? _error;

  /// The last restore queued, or null after a refusal or before the first.
  FilesRestoreResult? get result => _result;

  /// The thrown object from the last refused [restore].
  Object? get error => _error;

  /// The sentence for [result], or null when there is none.
  String? get summary {
    final result = _result;
    return result == null ? null : restoreFilesSummary(result);
  }

  /// Starts restoring the files on [deviceSerial]. Success sets [result] and
  /// clears [error]; a throw does the opposite.
  Future<void> restore({
    required String deviceSerial,
    required bool missingToBuiltIn,
  }) async {
    try {
      _result = await _restoreFiles(
        deviceSerial: deviceSerial,
        missingToBuiltIn: missingToBuiltIn,
      );
      _error = null;
    } catch (e) {
      _error = e;
      _result = null;
    }
    notifyListeners();
  }
}

/// The sentence for [result]: how many drives' files are coming back, which
/// go to built-in storage, and which stay on the backup drive.
String restoreFilesSummary(FilesRestoreResult result) {
  final count = result.folders.length;
  final parts = [
    'Restoring files from $count ${count == 1 ? 'drive' : 'drives'}.',
  ];
  final toBuiltIn = [
    for (final f in result.folders)
      if (f.toBuiltIn) f.folder,
  ];
  if (toBuiltIn.isNotEmpty) {
    parts.add(
      '${toBuiltIn.join(', ')} ${toBuiltIn.length == 1 ? 'goes' : 'go'} to built-in storage.',
    );
  }
  if (result.missing.isNotEmpty) {
    final one = result.missing.length == 1;
    parts.add(
      '${result.missing.join(', ')} ${one ? 'stays' : 'stay'} on the backup '
      'drive: ${one ? 'its drive is' : 'their drives are'} not attached.',
    );
  }
  return parts.join(' ');
}
