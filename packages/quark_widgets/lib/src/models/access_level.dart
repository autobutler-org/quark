/// How much an account or a group may do with a shared file or folder.
enum AccessLevel {
  /// Open it and download it.
  read,

  /// Change it too: upload into it, rename, move and delete.
  write,

  /// Everything, and change who else has access.
  owner;

  /// The words the sharing widgets show for this level.
  String get label => switch (this) {
    AccessLevel.read => 'Can view',
    AccessLevel.write => 'Can edit',
    AccessLevel.owner => 'Owner',
  };

  /// One sentence saying what this level lets someone do, shown under the
  /// [label] wherever a level is chosen. The owner's also says who to give
  /// it to, because an owner can change everyone else's access.
  String get description => switch (this) {
    AccessLevel.read => 'Can open and download it.',
    AccessLevel.write => 'Can also upload, rename, move and delete.',
    AccessLevel.owner =>
      'Can do everything, including change who has access. '
          'Give this only to someone you trust with it.',
  };
}
