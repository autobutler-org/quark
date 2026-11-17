/// One drive a `FileSortViewSheet` lets the user show or hide.
///
/// The [id] is the caller's own handle on the drive, such as its device path;
/// the sheet only hands it back.
class FileDeviceChoice {
  /// Creates a choice labeled [label], identified by [id].
  const FileDeviceChoice({
    required this.id,
    required this.label,
    required this.selected,
  });

  /// What the sheet hands back when this drive is toggled, and the suffix of
  /// its key. Stable and unique within one sheet.
  final String id;

  /// The drive's name.
  final String label;

  /// Whether the listing shows this drive's files now.
  final bool selected;
}
