import 'dart:convert';

import 'package:quark/services/app_settings.dart';
import 'package:quark/services/authenticated_service.dart';
import 'package:quark/utils/error_text.dart';

/// What to do next, as `GET /api/v0/storage/protection` names it.
enum DataProtectionAction {
  /// Give the snapshot-backup role to a drive that does not have it.
  assignBackupRole,

  /// Back up onto a backup drive that could give the weakest data drive
  /// another counting copy.
  startBackup,

  /// Two backup copies exist. Keep one of those drives somewhere else.
  keepElsewhere,
}

/// One backup drive's copy of a data drive, from `dataDrives[].copies`.
class DataProtectionCopy {
  /// Creates a copy row from the response fields.
  const DataProtectionCopy({
    required this.backupSerial,
    required this.backupName,
    required this.copiedAt,
    required this.counts,
    this.reason,
  });

  /// The serial of the backup drive holding the copy. Empty for built-in
  /// storage.
  final String backupSerial;

  /// The backup drive's name.
  final String backupName;

  /// When the copy was written.
  final DateTime copiedAt;

  /// Whether this copy protects the drive. The level is the Quark's: the
  /// client does not add these up.
  final bool counts;

  /// Why [counts] is false, in the Quark's words. Null when it counts.
  final String? reason;
}

/// A drive holding files, from `dataDrives`: its level and each copy of it,
/// newest first.
class DataProtectionDataDrive {
  /// Creates a data drive row from the response fields.
  const DataProtectionDataDrive({
    required this.serial,
    required this.name,
    required this.level,
    this.copies = const [],
  });

  /// The drive's serial. Empty for built-in storage.
  final String serial;

  /// The drive's name.
  final String name;

  /// `unprotected`, `basic`, or `protected`.
  final String level;

  /// One per backup drive with a record of this drive, newest first.
  final List<DataProtectionCopy> copies;
}

/// One data drive a backup drive holds a copy of, from `backupDrives[].holds`.
class DataProtectionHeldCopy {
  /// Creates a held copy from the response fields.
  const DataProtectionHeldCopy({
    required this.serial,
    required this.name,
    required this.copiedAt,
  });

  /// The data drive's serial. Empty for built-in storage.
  final String serial;

  /// The data drive's name.
  final String name;

  /// When the copy was written.
  final DateTime copiedAt;
}

/// Where a backup drive stands, from `backupDrives[].state`.
enum DataProtectionBackupState {
  /// No copy of any data drive yet.
  noCopies('no-copies'),

  /// A backup onto it is pending or running.
  receiving('receiving'),

  /// It holds every data drive, each copied within 30 days.
  current('current'),

  /// It is missing a data drive, or a copy is more than 30 days old.
  behind('behind'),

  /// Unplugged. Its copies still count from their records.
  away('away'),

  /// Its health verdict is Replace soon, so its copies do not count.
  retired('retired');

  const DataProtectionBackupState(this.wire);

  /// The word the Quark sends.
  final String wire;
}

/// A snapshot-backup drive, from `backupDrives`: its state and the data
/// drives it holds, newest first.
class DataProtectionBackupDrive {
  /// Creates a backup drive row from the response fields.
  const DataProtectionBackupDrive({
    required this.serial,
    required this.name,
    required this.state,
    this.holds = const [],
    this.newestCopy,
  });

  /// The drive's serial. Empty for built-in storage.
  final String serial;

  /// The drive's name.
  final String name;

  /// Where the drive stands.
  final DataProtectionBackupState state;

  /// One per data drive this drive holds a copy of, newest first.
  final List<DataProtectionHeldCopy> holds;

  /// The newest of [holds]. Null when it holds nothing.
  final DateTime? newestCopy;
}

/// The protection status from `GET /api/v0/storage/protection`.
///
/// [level] is `unprotected`, `basic`, or `protected`: the weakest data
/// drive's. [sentence] is the one sentence the Quark wrote. [action] is
/// `assign-backup-role`, `start-backup`, or `keep-one-elsewhere`.
/// [dataDrives] are the drives holding files, [backupDrives] the drives they
/// are copied onto.
class DataProtectionStatus {
  /// Creates a status the Quark has already decided.
  const DataProtectionStatus({
    required this.level,
    required this.sentence,
    required this.action,
    this.dataDrives = const [],
    this.backupDrives = const [],
  });

  /// Parses the JSON body of `GET /api/v0/storage/protection`.
  factory DataProtectionStatus.fromJson(Map<String, dynamic> json) {
    final level = json['level'];
    final sentence = json['sentence'];
    final nextStep = json['nextStep'];
    if (level is! String || sentence is! String || nextStep is! String) {
      throw const FormatException('Invalid protection status');
    }
    return DataProtectionStatus(
      level: _level(level),
      sentence: sentence,
      action: _action(nextStep),
      dataDrives: [
        for (final item in _maps(json['dataDrives']))
          DataProtectionDataDrive(
            serial: item['serial'] as String? ?? '',
            name: item['name'] as String? ?? '',
            level: _level(item['level']),
            copies: [
              for (final copy in _maps(item['copies']))
                DataProtectionCopy(
                  backupSerial: copy['backupSerial'] as String? ?? '',
                  backupName: copy['backupName'] as String? ?? '',
                  copiedAt: _at(copy['copiedAt']),
                  counts: copy['counts'] as bool? ?? false,
                  reason: _reason(copy['reason']),
                ),
            ],
          ),
      ],
      backupDrives: [
        for (final item in _maps(json['backupDrives']))
          DataProtectionBackupDrive(
            serial: item['serial'] as String? ?? '',
            name: item['name'] as String? ?? '',
            state: _state(item['state']),
            holds: [
              for (final held in _maps(item['holds']))
                DataProtectionHeldCopy(
                  serial: held['serial'] as String? ?? '',
                  name: held['name'] as String? ?? '',
                  copiedAt: _at(held['copiedAt']),
                ),
            ],
            newestCopy: _time(item['newestCopy']),
          ),
      ],
    );
  }

  /// `unprotected`, `basic`, or `protected`.
  final String level;

  /// The Quark's one sentence.
  final String sentence;

  /// The one recommended action.
  final DataProtectionAction action;

  /// Every connected drive that is not a backup drive, built-in storage
  /// first.
  final List<DataProtectionDataDrive> dataDrives;

  /// Every snapshot-backup drive, connected or not.
  final List<DataProtectionBackupDrive> backupDrives;

  /// The data drive with [serial], or null when it is not one.
  DataProtectionDataDrive? dataDrive(String serial) =>
      dataDrives.where((d) => d.serial == serial).firstOrNull;

  /// The backup drive with [serial], or null when it is not one.
  DataProtectionBackupDrive? backupDrive(String serial) =>
      backupDrives.where((d) => d.serial == serial).firstOrNull;
}

Iterable<Map<String, dynamic>> _maps(Object? raw) =>
    raw is List ? raw.whereType<Map<String, dynamic>>() : const [];

DataProtectionBackupState _state(Object? raw) {
  for (final state in DataProtectionBackupState.values) {
    if (state.wire == raw) return state;
  }
  throw const FormatException('Invalid protection status');
}

String _level(Object? raw) {
  switch (raw) {
    case 'unprotected':
    case 'basic':
    case 'protected':
      return raw as String;
    default:
      throw const FormatException('Invalid protection status');
  }
}

DataProtectionAction _action(String raw) {
  switch (raw) {
    case 'assign-backup-role':
      return DataProtectionAction.assignBackupRole;
    case 'start-backup':
      return DataProtectionAction.startBackup;
    case 'keep-one-elsewhere':
      return DataProtectionAction.keepElsewhere;
    default:
      throw const FormatException('Invalid protection status');
  }
}

String? _reason(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return raw;
}

DateTime _at(Object? raw) =>
    _time(raw) ?? (throw const FormatException('Invalid protection status'));

DateTime? _time(Object? raw) {
  if (raw == null) return null;
  if (raw is! String || raw.isEmpty) {
    throw const FormatException('Invalid protection status');
  }
  return DateTime.parse(raw);
}

/// Reads `GET /api/v0/storage/protection`.
///
/// The body is the level, one sentence, the next step, each data drive's
/// copies, and what each backup drive holds. This client shows that level.
/// It does not count copies again.
class DataProtectionService with AuthenticatedService {
  DataProtectionService._();

  /// The shared service.
  static final DataProtectionService instance = DataProtectionService._();

  /// Fetches the current protection status.
  ///
  /// api: GET /api/v0/storage/protection
  static Future<DataProtectionStatus> fetch() async {
    final response = await instance.authenticatedGet(
      apiBaseUri.resolve('/api/v0/storage/protection'),
    );
    final status = response.statusCode;
    if (status >= 200 && status < 300) {
      final body = jsonDecode(response.body);
      if (body is! Map<String, dynamic>) {
        throw const FormatException('Invalid protection status');
      }
      return DataProtectionStatus.fromJson(body);
    }
    throw ApiException(status, 'check the backup');
  }
}
