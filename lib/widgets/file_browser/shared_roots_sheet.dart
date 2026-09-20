import 'package:flutter/material.dart';
import 'package:quark/models/path_grant.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks which of the folders shared with the signed-in account to open, and
/// answers with its path or null when the sheet was dismissed (#2139).
///
/// The caller already holds [roots] — it is what decided the Shared with me
/// shortcut was worth offering — so the sheet never loads anything.
Future<String?> showSharedRootsSheet(
  BuildContext context,
  List<SharedRoot> roots,
) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  builder: (sheetContext) => SharedRootsSheet(
    items: [
      for (final root in roots)
        SharedRootItem(path: root.relPath, name: root.name, owner: root.owner),
    ],
    onPicked: (path) => Navigator.of(sheetContext).pop(path),
  ),
);
