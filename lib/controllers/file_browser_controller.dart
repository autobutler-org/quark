import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:quark/models/file_node.dart';
import 'package:quark/services/auth_service.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/services/file_browser_actions.dart';
import 'package:quark/services/slides_service.dart';
import 'package:quark/services/storage_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_browser_landing_config.dart';
import 'package:quark/utils/folder_picker.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/quark_widget.dart';
import 'package:quark/utils/upload_tree_utils.dart';
import 'package:quark/widgets/file_browser/file_browser_view.dart';
import 'package:quark/widgets/sharing/show_share_sheet.dart';
import 'package:quark/widgets/slides/import/import_power_point.dart';
import 'package:quark/widgets/video_viewer/convert_video.dart';

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

/// The Files page's calls to the Quark and the platform: listing a folder, picking and uploading files, folders
/// and photos, creating folders, deleting, and the actions in a file's menu.
class FileBrowserController {
  const FileBrowserController({
    this.deleteFiles = FilesService.deleteFiles,
    this.listTranscodeFormats = FilesService.listTranscodeFormats,
    this.transcodeVideo = FilesService.transcodeVideo,
    this.importPowerPoint = SlidesService.importPowerPoint,
    this.saveNode = downloadNode,
    this.saveArchiveFile = FilesService.saveArchiveFile,
    this.saveBytesToFile = FilesService.saveBytesToFile,
  });

  /// The saves behind Download, injectable so a test can fake them. Each
  /// answers null when the user canceled the save dialog (#3212).
  final Future<String?> Function({required FileNode node}) saveNode;
  final Future<String?> Function(
    String archivePath,
    String entryPath, {
    String? serial,
    String? fileName,
  })
  saveArchiveFile;
  final Future<String?> Function(Uint8List bytes, String fileName)
  saveBytesToFile;

  /// The batch delete call, injectable so a test can see the batches.
  final DeleteFilesFn deleteFiles;

  /// The formats Convert video offers for a video, injectable so a test can
  /// fake them.
  final LoadTranscodeFormatsFn listTranscodeFormats;

  /// The call Convert video queues its job with, injectable so a test can
  /// see it.
  final TranscodeVideoFn transcodeVideo;

  /// The call Open as presentation imports a PowerPoint file with,
  /// injectable so a test can fake it.
  final Future<PowerPointImport> Function(String path, {String? serial})
  importPowerPoint;

  /// The `serial` filter for the devices whose paths are in [activePaths]:
  /// null when every known device is selected (no filter), otherwise their
  /// serials, with `''` naming the internal drive (#3201). An empty filter
  /// means every device to the backend, so the blank serial must be sent.
  static List<String>? serialFilter(
    List<StorageDevice> devices,
    Set<String> activePaths,
  ) {
    final selected = devices
        .where((d) => activePaths.contains(d.devicePath))
        .toList();
    if (selected.length == devices.length) return null;
    return [for (final d in selected) d.serial];
  }

  /// Waits, for no longer than [FileBrowserLandingConfig.accountWait], for
  /// the Quark to say whether the signed-in account is an admin, which decides
  /// where a bare `/files` opens (#3211). Answers what went wrong, a
  /// [TimeoutException] when it took too long, or null when the admin flag is
  /// the Quark's answer.
  Future<Object?> settleAccount() => AuthService.accountSettled().timeout(
    FileBrowserLandingConfig.accountWait,
    onTimeout: () => TimeoutException(
      'auth status still pending',
      FileBrowserLandingConfig.accountWait,
    ),
  );

  Future<List<FileNode>> fetchFiles(
    String currentPath, {
    List<String>? serials,
  }) {
    return FilesService.getFiles(currentPath, serials: serials);
  }

  /// What [currentPath] holds on the one drive whose serial is [serial] —
  /// empty for the internal drive.
  ///
  /// The Quark reads an empty serial filter as every drive, so the internal
  /// drive is the merged listing less what sits on another drive. That is
  /// exact: the merged listing reports a folder on several drives once, as the
  /// internal drive's when it has one.
  Future<List<FileNode>> fetchDeviceFiles(
    String currentPath,
    String serial,
  ) async {
    if (serial.isNotEmpty) return fetchFiles(currentPath, serials: [serial]);
    return [
      for (final node in await fetchFiles(currentPath))
        if (node.deviceSerial.isEmpty) node,
    ];
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

  Future<String?> promptFolderName(BuildContext context) {
    return promptForFolderName(context);
  }

  /// Creates [folderName] in [currentPath] on the device with [serial], or on
  /// built-in storage when it is null.
  Future<void> createFolder({
    required String currentPath,
    required String folderName,
    String? serial,
  }) {
    return createFolderAtCurrentPath(
      currentPath: currentPath,
      folderName: folderName,
      serial: serial,
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
        final savedPath = await saveNode(node: node);
        if (savedPath == null) return null;
        return FileMenuActionOutcome(message: downloadedMessage(node));
      case FileMenuAction.moveRename:
        final startPath = parentPath(node.apiPath);
        final nodeSerial = node.deviceSerial.trim();
        // Fetch devices for cross-device move support. Only mounted drives
        // are destinations — moving to any other answers 404 — plus the
        // item's own drive, so the picker always has where it is now. Mount
        // state is fresh: mounting and unmounting invalidate the device
        // cache (#1042).
        List<StorageDevice> devices = [];
        try {
          devices = [
            for (final d in await StorageService.listDevices())
              if (d.isEnabled || d.serial == nodeSerial) d,
          ];
        } catch (_) {
          // Fall through with empty list — dialog will skip device picker
        }
        if (!context.mounted) return null;
        final moveResult = await promptForMoveRenamePath(
          context,
          startPath: startPath,
          initialName: node.name,
          devices: devices,
          deviceSerial: nodeSerial,
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
          currentDeviceSerial: nodeSerial,
          targetDeviceSerial: moveResult.deviceSerial,
        );
        if (targetPath == null) {
          return null;
        }

        // Prevent moving a directory into itself or its own subtree. On
        // another drive the same path is a different folder.
        if (node.isDir &&
            (moveResult.deviceSerial ?? nodeSerial) == nodeSerial) {
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
      case FileMenuAction.share:
        // The sheet reports its own refusals, so there is nothing to add.
        await showShareSheet(
          context,
          deviceSerial: node.deviceSerial,
          relPath: node.apiPath,
          name: trimTrailingSlashes(node.name),
        );
        return null;
      case FileMenuAction.convertVideo:
        // The flow reports its own outcome, as it does in the video viewer.
        await convertVideo(
          context,
          relPath: node.apiPath,
          serial: serialOrNull(node.deviceSerial),
          loadFormats: listTranscodeFormats,
          transcode: transcodeVideo,
        );
        return null;
      case FileMenuAction.openAsPresentation:
        // The flow reports its own outcome, as it does on the Slides page.
        final serial = serialOrNull(node.deviceSerial);
        await importPowerPointAndOpen(
          context,
          name: node.name,
          run: () => importPowerPoint(node.apiPath, serial: serial),
          serial: serial,
        );
        return null;
      case FileMenuAction.restore:
      case FileMenuAction.deletePermanently:
        // Trash-only actions; the Files page never offers them.
        return null;
    }
  }

  /// What to tell the user when [action] threw [error]. Every action gets a
  /// sentence: a refused move used to roll back with no word at all (#2178).
  String failureMessage(FileMenuAction action, Object? error) =>
      Errors.message(error, switch (action) {
        FileMenuAction.download => 'download the file',
        FileMenuAction.moveRename => 'move or rename the item',
        FileMenuAction.delete ||
        FileMenuAction.deletePermanently => 'delete the item',
        FileMenuAction.extractHere => 'extract the archive',
        FileMenuAction.navigateToFolder => 'open the folder',
        FileMenuAction.share => 'share the item',
        FileMenuAction.restore => 'restore the item',
        FileMenuAction.convertVideo => 'convert the video',
        FileMenuAction.openAsPresentation => 'import the presentation',
      });

  /// The path a move of [nodeApiPath] to [targetInput] lands on, or null when
  /// there is nothing to do: the path and the device are both unchanged.
  ///
  /// [targetDeviceSerial] is the destination drive, empty for the internal
  /// one; null means none was chosen, which is [currentDeviceSerial].
  String? resolveMoveRenameTargetPath({
    required String currentPath,
    required String nodeApiPath,
    required String targetInput,
    String currentDeviceSerial = '',
    String? targetDeviceSerial,
  }) {
    final oldPath = normalizePath(nodeApiPath);
    final targetPath = targetInput.startsWith('/')
        ? normalizePath(targetInput)
        : joinPath(currentPath, targetInput);
    final sameDevice =
        (targetDeviceSerial ?? currentDeviceSerial) == currentDeviceSerial;

    if (targetPath.isEmpty || (targetPath == oldPath && sameDevice)) {
      return null;
    }

    return targetPath;
  }

  /// Where opening [node] goes.
  ///
  /// A directory opens at [FileNode.apiPath], the path the listing already
  /// gave it. Joining [node.name] onto [currentPath] repeats the segment when
  /// the row is still the parent's (#2075). A file has no path of its own and
  /// still joins its name onto [currentPath].
  String nextPathForOpenDirectory({
    required String currentPath,
    required FileNode node,
  }) {
    if (node.isDir && node.apiPath.isNotEmpty) {
      return normalizePath(node.apiPath);
    }
    return joinPath(currentPath, node.name);
  }

  String nextPathForGoUp(String currentPath) {
    return parentPath(currentPath);
  }

  String downloadedMessage(FileNode node) {
    return 'Downloaded ${trimTrailingSlashes(node.name)}';
  }

  /// Saves the archive entry [entryPath] from the archive on device [serial]
  /// (null for the built-in drive) and answers the message to show, or null
  /// when the user canceled the save.
  Future<String?> saveArchiveEntry(
    String archivePath,
    String entryPath, {
    required String name,
    String? serial,
  }) async {
    final saved = await saveArchiveFile(
      archivePath,
      entryPath,
      serial: serial,
      fileName: name,
    );
    return saved == null ? null : 'Downloaded $name';
  }

  /// Saves [bytes] as [name] and answers the message to show, or null when
  /// the user canceled the save.
  Future<String?> saveBytes(Uint8List bytes, String name) async {
    final saved = await saveBytesToFile(bytes, name);
    return saved == null ? null : 'Downloaded $name';
  }
}
