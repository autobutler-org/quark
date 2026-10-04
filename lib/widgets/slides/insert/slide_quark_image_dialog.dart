import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Picks a picture already on the Quark for a slide (#1158): a dialog that
/// browses folders from [startPath], listing subfolders and pictures, and
/// pops with the chosen picture's files-relative path. "Up" climbs to the
/// parent folder; Cancel pops with null.
///
/// It lists through [listFolder], so a test passes a fake. A listing that
/// fails says so in the app's words and offers to try again.
///
/// Key prefixes: `slide_quark_image_dialog` on the dialog,
/// `slide_quark_image_up` on Up, `slide_quark_image_folder_<name>` and
/// `slide_quark_image_file_<name>` on the rows, `slide_quark_image_retry`
/// on retry.
class SlideQuarkImageDialog extends StatefulWidget {
  /// A dialog opening on [startPath].
  const SlideQuarkImageDialog({
    required this.startPath,
    required this.listFolder,
    super.key,
  });

  /// The folder shown first, relative to the files root; empty for the root.
  final String startPath;

  /// Lists the folder at a path.
  final Future<List<FileNode>> Function(String path) listFolder;

  /// Shows the dialog and completes with the chosen path, or null.
  static Future<String?> show(
    BuildContext context, {
    required String startPath,
    required Future<List<FileNode>> Function(String path) listFolder,
  }) => showDialog<String>(
    context: context,
    builder: (_) =>
        SlideQuarkImageDialog(startPath: startPath, listFolder: listFolder),
  );

  @override
  State<SlideQuarkImageDialog> createState() => _SlideQuarkImageDialogState();
}

class _SlideQuarkImageDialogState extends State<SlideQuarkImageDialog> {
  late String _path = _clean(widget.startPath);
  late Future<List<FileNode>> _listing = widget.listFolder(_path);

  static String _clean(String path) =>
      path.trim().replaceAll(RegExp(r'^/+|/+$'), '');

  void _open(String path) => setState(() {
    _path = _clean(path);
    _listing = widget.listFolder(_path);
  });

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return AlertDialog(
      key: const ValueKey('slide_quark_image_dialog'),
      title: const Text('Choose a picture'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                QuarkBarIconButton(
                  key: const ValueKey('slide_quark_image_up'),
                  icon: QuarkIcons.arrow_upward_rounded,
                  tooltip: 'Up one folder',
                  onPressed: _path.isEmpty
                      ? null
                      : () => _open(parentPath(_path)),
                ),
                Expanded(
                  child: Text(
                    _path.isEmpty ? 'Files' : _path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            Divider(height: 1, color: tokens.border),
            Expanded(
              child: FutureBuilder<List<FileNode>>(
                future: _listing,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            Errors.message(snapshot.error, 'list this folder'),
                            textAlign: TextAlign.center,
                          ),
                          TextButton(
                            key: const ValueKey('slide_quark_image_retry'),
                            onPressed: () => _open(_path),
                            child: const Text('Try again'),
                          ),
                        ],
                      ),
                    );
                  }
                  final nodes = snapshot.data;
                  if (nodes == null) {
                    return const Center(child: QuarkLoader(size: 20));
                  }
                  final entries = [
                    for (final n in nodes)
                      if (n.isDir) n,
                    for (final n in nodes)
                      if (!n.isDir && fileKindForName(n.name) == FileKind.image)
                        n,
                  ];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        'No pictures or folders here',
                        style: TextStyle(color: tokens.mutedForeground),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final node = entries[i];
                      return ListTile(
                        key: ValueKey(
                          node.isDir
                              ? 'slide_quark_image_folder_${node.name}'
                              : 'slide_quark_image_file_${node.name}',
                        ),
                        leading: Icon(
                          node.isDir
                              ? QuarkIcons.folder_outlined
                              : QuarkIcons.image_outlined,
                        ),
                        title: Text(node.name),
                        onTap: () => node.isDir
                            ? _open(node.apiPath)
                            : Navigator.of(context).pop(node.apiPath),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
