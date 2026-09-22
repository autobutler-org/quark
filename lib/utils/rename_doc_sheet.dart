import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/file_browser_actions.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

final _extension = RegExp(r'\.(qdoc|qsheet)$', caseSensitive: false);

/// Asks for a new name for a doc or sheet and renames it in place, keeping its
/// extension. Returns whether the file was renamed.
///
/// [siblings] is every file the page has listed. A move onto a taken path
/// replaces what is there, so a name another listed file in the same folder
/// already has is refused here rather than sent.
Future<bool> renameDocOrSheet(
  BuildContext context,
  FileNode node, {
  required Iterable<FileNode> siblings,
}) async {
  final extension = _extension.firstMatch(node.name)?.group(0) ?? '';
  final currentName = node.name.substring(
    0,
    node.name.length - extension.length,
  );
  final isSheet = extension.toLowerCase() == '.qsheet';
  final name = await promptForNewFileName(
    context,
    title: isSheet ? 'Rename spreadsheet' : 'Rename document',
    hintText: isSheet ? 'Spreadsheet name' : 'Document name',
    confirmLabel: 'Rename',
    initialName: currentName,
  );
  if (name == null || name == currentName || !context.mounted) return false;

  final newFileName = '$name$extension';
  final newPath = joinPath(parentPath(node.apiPath), newFileName).toLowerCase();
  final taken = siblings.any(
    (other) =>
        other.deviceSerial == node.deviceSerial &&
        other.apiPath != node.apiPath &&
        normalizePath(other.apiPath).toLowerCase() == newPath,
  );
  if (taken) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text(Errors.fileNameTaken)));
    return false;
  }

  try {
    await moveRenameNode(node: node, targetInput: newFileName);
    return true;
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Errors.message(e, isSheet ? 'rename the sheet' : 'rename the doc'),
          ),
        ),
      );
    }
    return false;
  }
}
