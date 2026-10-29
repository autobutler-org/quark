import 'package:flutter/widgets.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_dialog_utils.dart';
import 'package:quark/utils/file_browser_path_utils.dart';

/// Whether the signed-in account may delete [node].
///
/// An admin may. A member may when the file is in their home on the internal
/// drive (#2139). See [canWritePath].
bool canDeleteListedFile(FileNode node) => canWritePath(
  isAdmin: AppSettings.instance.isAdmin.value,
  username: AppSettings.instance.username,
  serial: node.deviceSerial,
  path: node.apiPath,
);

/// Moves [node] to Trash after a confirmation, the way Files does, on the
/// node's own device.
///
/// Returns true when it was moved. Cancel, a disposed context, or a failed
/// delete returns false. A failure tells the user what happened and does not
/// claim the file is gone.
Future<bool> deleteDocOrSheet(BuildContext context, FileNode node) async {
  final confirmed = await confirmDelete(
    context,
    node.name.replaceAll(RegExp(r'/+$'), ''),
  );
  if (confirmed != true || !context.mounted) return false;
  try {
    await FilesService.deleteFile(
      toRootDir(parentPath(node.apiPath)),
      trimTrailingSlashes(node.name),
      deviceSerial: serialOrNull(node.deviceSerial),
    );
  } catch (e) {
    if (context.mounted) {
      showMessage(context, Errors.message(e, 'delete the ${_noun(node)}'));
    }
    return false;
  }
  if (!context.mounted) return false;
  showMessage(context, 'Deleted');
  return true;
}

/// The noun in "Couldn't delete the …", picked from the file's extension.
String _noun(FileNode node) {
  final name = node.name.toLowerCase();
  if (name.endsWith('.qsheet')) return 'sheet';
  if (name.endsWith('.qslide')) return 'presentation';
  return 'document';
}
