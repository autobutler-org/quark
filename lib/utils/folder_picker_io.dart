import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:quark/services/upload_chunk_source_io.dart';
import 'package:quark/utils/upload_tree_utils.dart';

/// Desktop can open a directory chooser; mobile cannot.
///
/// [FilePicker.getDirectoryPath] is implemented for Linux, macOS and Windows.
/// On Android it returns protected or unusable paths and on iOS there is no
/// equivalent at all, so folder upload is not offered there.
bool get isFolderPickerSupportedPlatform =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// Native iOS uses the Files document picker for [FileType.any], which cannot
/// see the Camera Roll. Android's picker already includes the gallery.
bool get isPhotoLibraryPickerNeededPlatform => Platform.isIOS;

Future<List<PendingUpload>> pickFolderUploadsPlatform() async {
  if (!isFolderPickerSupportedPlatform) {
    return const [];
  }

  final rootPath = await FilePicker.getDirectoryPath(
    dialogTitle: 'Select folder to upload',
  );
  if (rootPath == null || rootPath.trim().isEmpty) {
    return const [];
  }

  final root = Directory(rootPath);
  if (!root.existsSync()) {
    return const [];
  }

  final uploads = <PendingUpload>[];
  // followLinks: false — a symlink out of the chosen folder is exactly the
  // traversal this feature must not perform, and sanitizeRelativeDir cannot
  // see it because the resulting relative path looks ordinary.
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File) {
      continue;
    }
    if (uploads.length >= kMaxUploadFiles) {
      break;
    }

    final relativePath = _relativeTo(root.path, entity.path);
    final relativeDir = sanitizeRelativeDir(relativeDirOf(relativePath));
    if (relativeDir == null) {
      continue;
    }

    final name = _basename(relativePath).trim();
    if (name.isEmpty) {
      continue;
    }

    uploads.add(
      PendingUpload(
        relativeDir: relativeDir,
        name: name,
        // fromPath streams off disk, so a large folder never lands in memory
        // all at once. Unchanged by #1629: this is the small-file path, and it
        // was already the thing the web side had to be taught.
        build: () async {
          try {
            return await http.MultipartFile.fromPath(
              'files',
              entity.path,
              filename: name,
            );
          } catch (e) {
            debugPrint('[folder_picker_io.dart] Failed to read $name: $e');
            return null;
          }
        },
        openChunkSource: () => FileUploadChunkSource.open(entity.path),
      ),
    );
  }

  return uploads;
}

/// [filePath] expressed relative to [rootPath], with `/` separators.
///
/// Directory.list yields absolute paths under the directory it was given, so
/// stripping that prefix is enough — no path package needed for a job this
/// narrow.
String _relativeTo(String rootPath, String filePath) {
  var relative = filePath;
  if (relative.startsWith(rootPath)) {
    relative = relative.substring(rootPath.length);
  }
  return relative.replaceAll(r'\', '/').replaceAll(RegExp(r'^/+'), '');
}

String _basename(String relativePath) {
  final lastSlash = relativePath.lastIndexOf('/');
  return lastSlash < 0 ? relativePath : relativePath.substring(lastSlash + 1);
}

/// Plain file selection.
///
/// Nothing here reads a file at pick time: every native picker hands back a
/// real path, and pulling the bytes as well would put the whole file in memory
/// for nothing — the same waste #1629 removed from the web side. A picker that
/// somehow returns no path still works: that file falls back to the picker's
/// own byte stream, which is read lazily at upload time and takes the
/// single-request path.
Future<List<PendingUpload>> pickFileUploadsPlatform() async {
  return _pendingUploadsFromPicker(await FilePicker.pickFiles());
}

/// Photos and videos from the device library.
///
/// [FileType.media] is the PHPicker on iOS, which is the Camera Roll.
/// [FileType.any] (used by [pickFileUploadsPlatform]) is the Files app.
Future<List<PendingUpload>> pickPhotoUploadsPlatform() async {
  return _pendingUploadsFromPicker(
    await FilePicker.pickFiles(type: FileType.media),
  );
}

List<PendingUpload> _pendingUploadsFromPicker(List<PlatformFile> result) {
  if (result.isEmpty) {
    return const [];
  }

  final uploads = <PendingUpload>[];
  for (final picked in result) {
    final name = picked.name.trim();
    if (name.isEmpty) {
      continue;
    }

    final path = picked.path;
    if (path == null || path.isEmpty) {
      uploads.add(
        PendingUpload(
          relativeDir: '',
          name: name,
          build: () async => http.MultipartFile(
            'files',
            picked.readAsByteStream(),
            await picked.length(),
            filename: name,
          ),
        ),
      );
      continue;
    }

    uploads.add(
      PendingUpload(
        relativeDir: '',
        name: name,
        build: () async {
          try {
            return await http.MultipartFile.fromPath(
              'files',
              path,
              filename: name,
            );
          } catch (e) {
            debugPrint('[folder_picker_io.dart] Failed to read $name: $e');
            return null;
          }
        },
        openChunkSource: () => FileUploadChunkSource.open(path),
      ),
    );
  }

  return uploads;
}
