/// What to do about an upload the Quark refused because the name is taken.
///
/// The Quark never renames a file on its own (#2016): an upload whose name is
/// in use comes back as a 409, and one of these says how to send it again.
enum UploadConflictChoice {
  /// Land the new file under the first free name — `holiday_(1).jpg`.
  keepBoth,

  /// Replace what is already there. Needs write access; the file keeps the
  /// owner it already had.
  replace,
}

/// One answer to one name clash.
class UploadConflictAnswer {
  const UploadConflictAnswer({required this.choice, this.applyToAll = false});

  /// What to do with this file, or null to leave it unsent.
  final UploadConflictChoice? choice;

  /// Whether the same answer stands for every later clash in this upload.
  final bool applyToAll;
}
