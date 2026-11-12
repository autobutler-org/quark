import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:quark/widgets/file_browser/file_browser_view/file_menu.dart';
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

/// Moves one file or folder — [FilesService.moveFile].
typedef MoveFileFn =
    Future<void> Function(
      String oldPath,
      String newPath, {
      String? oldDeviceSerial,
      String? newDeviceSerial,
    });

/// What moving a selection did, and what to tell the person who asked.
///
/// [leaveSelection] is true only when every selected item is where it was
/// asked to be. A skip or a refusal leaves the rest selected (#3989).
class MoveSelectionOutcome {
  const MoveSelectionOutcome({
    required this.moved,
    required this.failed,
    required this.left,
    required this.intoSelf,
    required this.movedPaths,
    required this.unchanged,
  });

  /// How many items the Quark accepted a move for.
  final int moved;

  /// How many moves the Quark refused. The ones in [moved] stay moved.
  final int failed;

  /// Names the context menu would not move, so they stayed put.
  final List<String> left;

  /// Folder names that would have landed inside themselves.
  final List<String> intoSelf;

  /// Paths that no longer need to stay selected: they moved, or they were
  /// already in the destination.
  final List<String> movedPaths;

  /// How many selected items were already at the destination.
  final int unchanged;

  /// Selection mode ends only when nothing selected was skipped or refused.
  bool get leaveSelection => failed == 0 && left.isEmpty && intoSelf.isEmpty;

  /// The sentence for the snack bar. Empty when there is nothing to say.
  String get message {
    final parts = <String>[
      if (moved == 1) 'Moved 1 item.' else if (moved > 1) 'Moved $moved items.',
      if (failed == 1)
        Errors.couldNot('move 1 item')
      else if (failed > 1)
        Errors.couldNot('move $failed items'),
      if (left.length == 1)
        'Left ${left.single} where it is.'
      else if (left.length > 1)
        'Left ${_nameList(left)} where they are.',
      if (intoSelf.length == 1)
        "${intoSelf.single} can't be moved into itself or one of its subfolders."
      else if (intoSelf.length > 1)
        "${_nameList(intoSelf)} can't be moved into themselves or one of their subfolders.",
    ];
    if (parts.isEmpty && unchanged > 0 && leaveSelection) {
      return 'Nothing was moved.';
    }
    return parts.join(' ');
  }
}

String _nameList(List<String> names) {
  if (names.length <= 1) return names.join();
  if (names.length == 2) return '${names[0]} and ${names[1]}';
  return '${names.sublist(0, names.length - 1).join(', ')}, and ${names.last}';
}

/// Whether a folder at [fromPath] on [fromSerial] would land inside itself
/// at [toPath] on [toSerial]. The same path on another device is a move.
bool folderLandsInsideItself({
  required bool isDir,
  required String fromPath,
  required String toPath,
  required String fromSerial,
  required String toSerial,
}) {
  if (!isDir) return false;
  if (fromSerial.trim() != toSerial.trim()) return false;
  final from = normalizePath(fromPath);
  final to = normalizePath(toPath);
  if (from.isEmpty) return false;
  return to == from || to.startsWith('$from/');
}

/// The Files page's calls to the Quark and the platform: listing a folder, picking and uploading files, folders
/// and photos, creating folders, deleting, moving a selection, and the actions in a file's menu.
class FileBrowserController {
  const FileBrowserController({
    this.deleteFiles = FilesService.deleteFiles,
    this.moveFile = FilesService.moveFile,
    this.createFolderAt = createFolderAtCurrentPath,
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

  /// One `PUT /api/v0/files`, injectable so a test can see each move.
  final MoveFileFn moveFile;

  /// Creates a folder, injectable so a test can refuse a taken name.
  final Future<void> Function({
    required String currentPath,
    required String folderName,
    String? serial,
  })
  createFolderAt;

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

  /// What [currentPath] holds; completing [abortTrigger] cancels the request.
  Future<List<FileNode>> fetchFiles(
    String currentPath, {
    List<String>? serials,
    Future<void>? abortTrigger,
  }) {
    return FilesService.getFiles(
      currentPath,
      serials: serials,
      abortTrigger: abortTrigger,
    );
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
    String serial, {
    Future<void>? abortTrigger,
  }) async {
    if (serial.isNotEmpty) {
      return fetchFiles(
        currentPath,
        serials: [serial],
        abortTrigger: abortTrigger,
      );
    }
    return [
      for (final node in await fetchFiles(
        currentPath,
        abortTrigger: abortTrigger,
      ))
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
    return createFolderAt(
      currentPath: currentPath,
      folderName: folderName,
      serial: serial,
    );
  }

  /// Asks where to put [nodes], then moves each one that can move.
  ///
  /// The picker is the Move/Rename browser without the name field. Null when
  /// the person cancels: nothing is moved and the selection is unchanged.
  /// [devices] is the list the page already holds (#3995).
  Future<MoveSelectionOutcome?> moveSelection({
    required BuildContext context,
    required List<FileNode> nodes,
    List<StorageDevice> devices = const [],
    required bool isAdmin,
    bool inArchive = false,
  }) async {
    if (nodes.isEmpty) return null;
    final serials = {for (final node in nodes) node.deviceSerial.trim()};
    final startSerial = nodes.first.deviceSerial.trim();
    final picked = await promptForMoveRenamePath(
      context,
      startPath: parentPath(nodes.first.apiPath),
      devices: [
        for (final device in devices)
          if (device.isEnabled || serials.contains(device.serial)) device,
      ],
      deviceSerial: startSerial,
      destinationOnly: true,
      onCreateFolder: (parent, name, serial) => createFolder(
        currentPath: parent,
        folderName: name,
        serial: serialOrNull(serial ?? ''),
      ),
    );
    if (picked == null || !context.mounted) return null;
    return moveNodes(
      nodes: nodes,
      destinationPath: picked.targetInput,
      destinationSerial: picked.deviceSerial,
      isAdmin: isAdmin,
      inArchive: inArchive,
    );
  }

  /// Moves [nodes] into [destinationPath], keeping each item's name.
  ///
  /// [destinationPath] is the folder, empty for the top of the device.
  /// [destinationSerial] is empty for built-in storage and null when each
  /// item stays on its own drive. One existing move per item. A refusal
  /// leaves the earlier moves in place.
  Future<MoveSelectionOutcome> moveNodes({
    required List<FileNode> nodes,
    required String destinationPath,
    String? destinationSerial,
    required bool isAdmin,
    bool inArchive = false,
  }) async {
    final left = <String>[];
    final intoSelf = <String>[];
    final movedPaths = <String>[];
    var moved = 0;
    var failed = 0;
    var unchanged = 0;
    final chosenSerial = destinationSerial?.trim();

    for (final node in nodes) {
      final display = trimTrailingSlashes(node.name);
      if (!canChangeFileNode(node, isAdmin: isAdmin, inArchive: inArchive)) {
        left.add(display);
        continue;
      }
      final target = joinPath(destinationPath, display);
      final nodeSerial = node.deviceSerial.trim();
      final landedSerial = chosenSerial ?? nodeSerial;
      if (normalizePath(target) == normalizePath(node.apiPath) &&
          landedSerial == nodeSerial) {
        unchanged++;
        movedPaths.add(node.apiPath);
        continue;
      }
      if (folderLandsInsideItself(
        isDir: node.isDir,
        fromPath: node.apiPath,
        toPath: target,
        fromSerial: nodeSerial,
        toSerial: landedSerial,
      )) {
        intoSelf.add(display);
        continue;
      }
      try {
        final serial = serialOrNull(node.deviceSerial);
        await moveFile(
          normalizePath(node.apiPath),
          normalizePath(target),
          oldDeviceSerial: serial,
          newDeviceSerial: destinationSerial == null
              ? serial
              : serialOrNull(destinationSerial),
        );
        moved++;
        movedPaths.add(node.apiPath);
      } catch (_) {
        failed++;
      }
    }

    return MoveSelectionOutcome(
      moved: moved,
      failed: failed,
      left: left,
      intoSelf: intoSelf,
      movedPaths: movedPaths,
      unchanged: unchanged,
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

  /// Runs [action] on [node]. [devices] is the device list the page already
  /// holds; Move/Rename offers its destinations from it rather than waiting
  /// on a device status call (#3995).
  Future<FileMenuActionOutcome?> handleFileAction({
    required FileNode node,
    required FileMenuAction action,
    required BuildContext context,
    List<StorageDevice> devices = const [],
  }) async {
    switch (action) {
      case FileMenuAction.download:
        final savedPath = await saveNode(node: node);
        if (savedPath == null) return null;
        return FileMenuActionOutcome(message: downloadedMessage(node));
      case FileMenuAction.moveRename:
        final startPath = parentPath(node.apiPath);
        final nodeSerial = node.deviceSerial.trim();
        // Only mounted drives are destinations — moving to any other
        // answers 404 — plus the item's own drive, so the picker always has
        // where it is now. The list is the page's: the status call behind a
        // fresh one runs disk detection and health reads, and waiting on it
        // held the dialog back and failed it as "not connected" (#3995).
        final moveResult = await promptForMoveRenamePath(
          context,
          startPath: startPath,
          initialName: node.name,
          devices: [
            for (final d in devices)
              if (d.isEnabled || d.serial == nodeSerial) d,
          ],
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
        if (folderLandsInsideItself(
          isDir: node.isDir,
          fromPath: node.apiPath,
          toPath: targetPath,
          fromSerial: nodeSerial,
          toSerial: moveResult.deviceSerial ?? nodeSerial,
        )) {
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

        await moveRenameNode(
          node: node,
          targetInput: targetInput,
          newDeviceSerial: moveResult.deviceSerial,
        );
        return const FileMenuActionOutcome(
          message: 'Move/Rename complete',
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
      case FileMenuAction.delete:
        // The page deletes, optimistically, before calling handleFileAction.
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
