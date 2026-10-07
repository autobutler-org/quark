/// A column the file list can show beside Name, which always shows.
///
/// This is the one definition of the optional columns: the order they sit in
/// (declaration order), their header label, the [SortColumn] their header
/// sorts by and the width they share. The list header and every row are built
/// from it, so the two cannot drift apart. [name] is what the choice is
/// stored under, so renaming a value forgets it.
enum FileListColumn {
  kind('Kind', SortColumn.type),
  modified('Modified', SortColumn.modified),
  device('Device', SortColumn.device),
  size('Size', SortColumn.size);

  const FileListColumn(this.label, this.sortColumn);

  /// The Name column's share of the row's width, beside each column's [flex].
  static const int nameFlex = 5;

  /// Every optional column's share of the row's width.
  static const int flex = 2;

  /// The header label, and the label in the column picker.
  final String label;

  /// What tapping the column's header sorts by.
  final SortColumn sortColumn;
}

/// Shows ([visible] true) or hides one column of the file list.
typedef FileListColumnToggle =
    void Function(FileListColumn column, bool visible);

/// What a file listing is sorted by. [type] is the Kind column.
enum SortColumn { name, type, modified, size, device }
