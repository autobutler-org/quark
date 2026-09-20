import 'package:http/http.dart' as http;
import 'package:quark/models/file_node.dart';
import 'package:quark/models/upload_conflict.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

Future<void> uploadMultipartFilesToCurrentPath({
  required String currentPath,
  required List<http.MultipartFile> selectedFiles,
  String? serial,
  UploadConflictChoice? conflict,
}) {
  return FilesService.uploadFilesFromFormData(
    toRootDir(currentPath),
    selectedFiles,
    serial: serial,
    overwrite: conflict == UploadConflictChoice.replace,
    keepBoth: conflict == UploadConflictChoice.keepBoth,
  );
}

Future<void> createFolderAtCurrentPath({
  required String currentPath,
  required String folderName,
}) {
  return FilesService.createFolder(toRootDir(currentPath), folderName);
}

Future<String?> downloadNode({required FileNode node}) {
  final itemName = trimTrailingSlashes(node.name);
  final filePath = node.apiPath;

  return FilesService.saveFile(
    filePath,
    serial: serialOrNull(node.deviceSerial),
    fileName: itemName,
  );
}

Future<void> moveRenameNode({
  required FileNode node,
  required String targetInput,
  String? newDeviceSerial,
}) {
  final basePath = parentPath(node.apiPath);
  final oldPath = normalizePath(node.apiPath);
  final targetPath = targetInput.startsWith('/')
      ? normalizePath(targetInput)
      : joinPath(basePath, targetInput);

  final serial = serialOrNull(node.deviceSerial);
  return FilesService.moveFile(
    oldPath,
    targetPath,
    oldDeviceSerial: serial,
    newDeviceSerial: newDeviceSerial ?? serial,
  );
}

Future<void> extractNode({required FileNode node}) {
  return FilesService.extractFile(
    node.apiPath,
    serial: serialOrNull(node.deviceSerial),
  );
}

Future<void> deleteNode({required FileNode node}) {
  final rootDir = toRootDir(parentPath(node.apiPath));
  return FilesService.deleteFile(
    rootDir,
    trimTrailingSlashes(node.name),
    deviceSerial: serialOrNull(node.deviceSerial),
  );
}
