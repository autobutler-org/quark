import 'package:flutter/foundation.dart';
import 'package:quark/models/file_list_column.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark/utils/model_thumbnail_config.dart';
import 'package:quark_widgets/quark_widgets.dart' show CalendarLabels;

/// Whether the server can render a thumbnail for this node. Videos go
/// through ffmpeg frame extraction on the backend and come back as JPEG,
/// so they use the same thumbnail URL as images. A 3D model has the one a
/// client drew when it was opened or uploaded (#3227).
bool hasServerThumbnail(FileNode node) =>
    !node.isDir &&
    (fileKindForName(node.name) == FileKind.video ||
        thumbnailImageExtensions.contains(fileExtension(node.name)) ||
        wantsModelThumbnail(node.name));

bool isArchiveNode(FileNode node) =>
    !node.isDir && fileKindForName(node.name) == FileKind.archive;

/// Identity of [node] for the list slot and the thumbnail in it.
///
/// A list or grid matches a child with no key by index. After the viewer
/// route is popped, that slot keeps the next file's image (#3355). The
/// serial is part of the key because two drives can list the same path.
ValueKey<String> fileThumbnailKey(FileNode node) =>
    ValueKey('${node.deviceSerial}:${node.apiPath}');

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
  final sizeStr = StorageDevice.formatBytes(bytes);
  if (compressedSize > 0 && compressedSize != bytes) {
    return '${StorageDevice.formatBytes(compressedSize)} → $sizeStr';
  }
  return sizeStr;
}
