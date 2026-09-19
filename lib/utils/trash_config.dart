/// What the app tells a user about the trash before anything has been
/// deleted (#2049).
abstract final class TrashConfig {
  /// How long a deleted item stays restorable, in days.
  ///
  /// Mirrors `storageutil.TrashRetentionDays`, the constant the hourly purge
  /// reads. The trash page does not use this number — it shows the
  /// `retentionDays` the listing returns, which is the Quark's own answer.
  /// This copy is needed before any trash call has been made, in the
  /// confirmation that decides whether the delete happens at all, so it
  /// states the built-in window rather than making the dialog wait on a
  /// request to word itself.
  static const int retentionDays = 30;
}
