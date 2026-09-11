import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/file_node.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/file_browser_actions.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/folder_picker.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/utils/upload_tree_utils.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';

class FileMenuActionOutcome {
  const FileMenuActionOutcome({
    required this.message,
    this.shouldRefresh = false,
  });

  final String message;
  final bool shouldRefresh;
}

/// Deletes [filePaths] under [rootDir] on one device — [FilesService.deleteFiles].
typedef DeleteFilesFn =
    Future<void> Function(
      List<String> filePaths, {
      String? rootDir,
      String? deviceSerial,
    });

class FileBrowserController {
  const FileBrowserController({this.deleteFiles = FilesService.deleteFiles});

  /// The batch delete call, injectable so a test can see the batches.
  final DeleteFilesFn deleteFiles;

  Future<List<FileNode>> fetchFiles(
    String currentPath, {
    List<String>? serials,
  }) {
    return FilesService.getFiles(currentPath, serials: serials);
  }

  /// Picks one or more files for upload.
  ///
  /// On web and desktop, multiple file selection is supported.
  /// On mobile (iOS/Android), the platform picker typically supports
  /// multi-select — enabled via [allowMultiple: true]. If the platform
  /// returns only a single file, the list will have one entry.
  ///
  /// Selects files only. For folders see [pickUploadFolder], which needs a
  /// different picker on every platform and so cannot share this entry point.
  ///
  /// Returns an empty list if the user cancelled.
  ///
  /// Returns [PendingUpload]s rather than built multipart files: the bytes are
  /// fetched when the file is sent, and a file large enough to be chunked has
  /// its bytes fetched a range at a time and never all at once (#1629). This
  /// used to go through file_picker with `withData: true`, which read every
  /// selected file into memory before anything was sent.
  Future<List<PendingUpload>> pickUploadFiles() {
    return pickFileUploads();
  }

  /// Whether this platform can offer folder selection at all.
  ///
  /// Web and desktop can; mobile has no meaningful folder picker, so callers
  /// hide the affordance rather than offering one that cannot work.
  bool get isFolderUploadSupported => isFolderPickerSupported;

  /// Whether this client must offer Photos as a source separate from Files.
  ///
  /// iOS's document picker is the Files app and cannot see the Camera Roll,
  /// so Photos is a distinct upload action there (#1797).
  bool get isPhotoUploadSupported => isPhotoLibraryPickerNeeded;

  /// Picks photos and videos from the device library.
  ///
  /// Same [PendingUpload] shape as [pickUploadFiles]. Empty if cancelled.
  Future<List<PendingUpload>> pickUploadPhotos() {
    return pickPhotoUploads();
  }

  /// Picks a folder and returns its files, each carrying the directory it sat
  /// in relative to the chosen folder.
  ///
  /// Returns an empty list if the user cancelled or the folder holds no files.
  Future<List<PendingUpload>> pickUploadFolder() {
    return pickFolderUploads();
  }

  http.MultipartFile multipartFileFromBytes({
    required Uint8List bytes,
    required String filename,
  }) {
    return http.MultipartFile.fromBytes('files', bytes, filename: filename);
  }

  Future<void> uploadFile({
    required String currentPath,
    required http.MultipartFile selectedFile,
    String? serial,
  }) {
    return uploadFiles(
      currentPath: currentPath,
      selectedFiles: [selectedFile],
      serial: serial,
    );
  }

  Future<void> uploadFiles({
    required String currentPath,
    required List<http.MultipartFile> selectedFiles,
    String? serial,
  }) {
    return uploadMultipartFilesToCurrentPath(
      currentPath: currentPath,
      selectedFiles: selectedFiles,
      serial: serial,
    );
  }

  Future<String?> promptFolderName(BuildContext context) {
    return promptForFolderName(context);
  }

  Future<void> createFolder({
    required String currentPath,
    required String folderName,
  }) {
    return createFolderAtCurrentPath(
      currentPath: currentPath,
      folderName: folderName,
    );
  }

  /// Delete a single node. Caller is responsible for confirmation and
  /// any optimistic UI updates.
  Future<void> deleteNode({required FileNode node}) {
    final rootDir = toRootDir(parentPath(node.apiPath));
    return FilesService.deleteFile(
      rootDir,
      trimTrailingSlashes(node.name),
      deviceSerial: serialOrNull(node.deviceSerial),
    );
  }

  /// Deletes [nodes] in one batch request per device and parent folder.
  ///
  /// The backend resolves each name against the request's `rootDir`, so a
  /// batch has to share a folder as well as a device. A selection can span
  /// folders — search results, recent files, the unified view — and batching
  /// by device alone sent every name to the first node's folder.
  Future<void> deleteNodes({required List<FileNode> nodes}) async {
    final batches = <(String?, String), List<String>>{};
    for (final n in nodes) {
      final key = (
        serialOrNull(n.deviceSerial),
        toRootDir(parentPath(n.apiPath)),
      );
      (batches[key] ??= []).add(trimTrailingSlashes(n.name));
    }
    for (final MapEntry(key: (serial, rootDir), value: names)
        in batches.entries) {
      await deleteFiles(names, rootDir: rootDir, deviceSerial: serial);
    }
  }

  Future<FileMenuActionOutcome?> handleFileAction({
    required FileNode node,
    required FileMenuAction action,
    required BuildContext context,
  }) async {
    switch (action) {
      case FileMenuAction.download:
        final savedPath = await downloadNode(node: node);
        if (savedPath == null) {
          return const FileMenuActionOutcome(message: 'Download canceled');
        }
        return FileMenuActionOutcome(message: downloadedMessage(node));
      case FileMenuAction.moveRename:
        final startPath = parentPath(node.apiPath);
        // Fetch devices for cross-device move support.
        // Use ALL devices (not just isEnabled) so the picker shows even
        // when mount state is stale — the user can still select a drive
        // that they know is mounted.
        List<StorageDevice> allDevices = [];
        try {
          allDevices = await StorageService.listDevices();
        } catch (_) {
          // Fall through with empty list — dialog will skip device picker
        }
        if (!context.mounted) return null;
        final moveResult = await promptForMoveRenamePath(
          context,
          startPath: startPath,
          initialName: node.name,
          devices: allDevices,
        );
        if (!context.mounted) {
          return null;
        }
        if (moveResult == null) {
          return null;
        }
        final targetInput = moveResult.targetInput;
        final targetPath = resolveMoveRenameTargetPath(
          currentPath: startPath,
          nodeApiPath: node.apiPath,
          targetInput: targetInput,
        );
        if (targetPath == null) {
          return null;
        }

        // Prevent moving a directory into itself or its own subtree
        if (node.isDir) {
          final normalizedOld = normalizePath(node.apiPath);
          final normalizedTarget = normalizePath(targetPath);
          if (normalizedTarget == normalizedOld ||
              normalizedTarget.startsWith('$normalizedOld/')) {
            // show an error dialog
            await QuarkWidget.showDialog<void>(
              context,
              useRootNavigator: true,
              builder: (dialogContext) => QuarkWidget.alertDialog(
                title: const Text('Invalid target'),
                content: const Text(
                  'Cannot move a folder into itself or one of its subfolders.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            return null;
          }
        }

        await moveRenameNode(
          node: node,
          targetInput: targetInput,
          newDeviceSerial: moveResult.deviceSerial,
        );
        return const FileMenuActionOutcome(
          message: 'Move/Rename complete',
          shouldRefresh: true,
        );
      case FileMenuAction.delete:
        final shouldDelete = await confirmDelete(
          context,
          trimTrailingSlashes(node.name),
        );
        if (shouldDelete != true) {
          return null;
        }
        await deleteNode(node: node);
        return const FileMenuActionOutcome(
          message: 'Deleted',
          shouldRefresh: true,
        );
      case FileMenuAction.extractHere:
        await extractNode(node: node);
        return const FileMenuActionOutcome(
          message: 'Extraction complete',
          shouldRefresh: true,
        );
      case FileMenuAction.navigateToFolder:
        // Handled via the onNavigateToFolder callback in FileBrowserView;
        // should never reach handleFileAction.
        return null;
      case FileMenuAction.restore:
      case FileMenuAction.deletePermanently:
        // Trash-only actions; the Files page never offers them.
        return null;
    }
  }

  String failureMessage(FileMenuAction action) {
    switch (action) {
      case FileMenuAction.download:
        return 'Download failed';
      case FileMenuAction.moveRename:
        return 'Move/Rename failed';
      case FileMenuAction.delete:
        return 'Delete failed';
      case FileMenuAction.extractHere:
        return 'Extraction failed';
      case FileMenuAction.navigateToFolder:
        return 'Navigation failed';
      case FileMenuAction.restore:
        return 'Restore failed';
      case FileMenuAction.deletePermanently:
        return 'Delete failed';
    }
  }

  String? resolveMoveRenameTargetPath({
    required String currentPath,
    required String nodeApiPath,
    required String targetInput,
  }) {
    final oldPath = normalizePath(nodeApiPath);
    final targetPath = targetInput.startsWith('/')
        ? normalizePath(targetInput)
        : joinPath(currentPath, targetInput);

    if (targetPath.isEmpty || targetPath == oldPath) {
      return null;
    }

    return targetPath;
  }

  String nextPathForOpenDirectory({
    required String currentPath,
    required FileNode node,
  }) {
    return joinPath(currentPath, node.name);
  }

  String nextPathForGoUp(String currentPath) {
    return parentPath(currentPath);
  }

  String downloadedMessage(FileNode node) {
    return 'Downloaded ${trimTrailingSlashes(node.name)}';
  }
}
