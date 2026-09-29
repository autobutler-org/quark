/// How an album list orders the user's albums. System albums keep their fixed
/// place at the top whatever the choice; ordering them is the caller's job.
enum AlbumSort {
  /// Name, A to Z. The default.
  nameAsc('name_asc', 'A–Z'),

  /// Name, Z to A.
  nameDesc('name_desc', 'Z–A'),

  /// Most recently created first.
  newest('newest', 'Newest'),

  /// Least recently created first.
  oldest('oldest', 'Oldest');

  const AlbumSort(this.id, this.label);

  /// A stable identifier, for persisting the choice and for key suffixes.
  final String id;

  /// The label a menu shows for this choice.
  final String label;
}
