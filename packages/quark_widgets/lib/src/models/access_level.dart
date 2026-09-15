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
}
