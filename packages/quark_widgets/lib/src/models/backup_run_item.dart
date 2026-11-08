import 'package:flutter/foundation.dart';

/// One backup on a backup drive, in the caller's words, as `BackupRunsList`
/// and `BackupRunPicker` show it.
@immutable
class BackupRunItem {
  /// Creates a run's data.
  const BackupRunItem({
    required this.id,
    required this.time,
    this.size = '',
    this.drives = '',
  });

  /// Identifies the run in callbacks: the folder the Quark names it by.
  final String id;

  /// When the run was taken, as "Nov 2, 09.00".
  final String time;

  /// How much the run holds, as "1.2 GB". Empty hides it.
  final String size;

  /// The drives the run holds, as "Built-in storage, Photos". Empty hides
  /// it.
  final String drives;
}
