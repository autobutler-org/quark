import 'package:quark/models/file_node.dart';
import 'package:quark/utils/file_kind.dart';

/// Whether the server can render a thumbnail for this node. Videos go
/// through ffmpeg frame extraction on the backend and come back as JPEG,
/// so they use the same thumbnail URL as images.
bool hasServerThumbnail(FileNode node) =>
    !node.isDir &&
    (fileKindForName(node.name) == FileKind.video ||
        thumbnailImageExtensions.contains(fileExtension(node.name)));

bool isArchiveNode(FileNode node) =>
    !node.isDir && fileKindForName(node.name) == FileKind.archive;

String formatFileSize(int bytes, bool isDir, {int compressedSize = 0}) {
  if (isDir) return '--';
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
