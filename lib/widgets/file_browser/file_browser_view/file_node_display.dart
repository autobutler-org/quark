import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark_widgets/quark_widgets.dart' show CalendarLabels;

/// Whether the server can render a thumbnail for this node. Videos go
/// through ffmpeg frame extraction on the backend and come back as JPEG,
/// so they use the same thumbnail URL as images.
bool hasServerThumbnail(FileNode node) =>
    !node.isDir &&
    (fileKindForName(node.name) == FileKind.video ||
        thumbnailImageExtensions.contains(fileExtension(node.name)));

bool isArchiveNode(FileNode node) =>
    !node.isDir && fileKindForName(node.name) == FileKind.archive;

/// What a cell shows when the listing has nothing to put in it: a folder's
/// size, or the time of a node the Quark sent none for.
const fileCellPlaceholder = '--';

/// What the Kind column shows for [node], and what its header sorts by.
String fileKindText(FileNode node) =>
    node.isDir ? 'Folder' : fileKindLabel(fileKindForName(node.name));

/// What [column] shows for [node]. A date reads "Oct 6, 2026", in the
/// viewer's own time zone.
String fileListCellText(FileListColumn column, FileNode node) =>
    switch (column) {
      FileListColumn.kind => fileKindText(node),
      FileListColumn.modified => switch (node.modifiedAt?.toLocal()) {
        null => fileCellPlaceholder,
        final time =>
          '${CalendarLabels.monthShort(time.month)} ${time.day}, ${time.year}',
      },
      FileListColumn.device => node.deviceName,
      FileListColumn.size => formatFileSize(
        node.size,
        node.isDir,
        compressedSize: node.compressedSize,
      ),
    };

String formatFileSize(int bytes, bool isDir, {int compressedSize = 0}) {
  if (isDir) return fileCellPlaceholder;
  final sizeStr = _formatBytes(bytes);
  if (compressedSize > 0 && compressedSize != bytes) {
    return '${_formatBytes(compressedSize)} → $sizeStr';
  }
  return sizeStr;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
}
