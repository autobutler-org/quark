import 'package:flutter/material.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/utils/file_kind.dart';
import 'package:quark_icons/quark_icons.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Picks a file already on the Quark for the slides — a picture for a slide
/// (#1158) by default, or a PowerPoint file to import (#1171): a dialog that
/// browses folders from [startPath], listing subfolders and the files
/// [accepts] lets through, and pops with the chosen file's files-relative
/// path. "Up" climbs to the parent folder; Cancel pops with null.
///
/// It lists through [listFolder], so a test passes a fake. A listing that
/// fails says so in the app's words and offers to try again.
///
/// Key prefixes, from [keyPrefix] (`slide_quark_image` by default):
/// `<prefix>_dialog` on the dialog, `<prefix>_up` on Up, `<prefix>_folder_<name>` and `<prefix>_file_<name>`
/// on the rows, `<prefix>_retry` on retry.
class SlideQuarkImageDialog extends StatefulWidget {
  /// A dialog opening on [startPath].
  const SlideQuarkImageDialog({
    required this.startPath,
    required this.listFolder,
    this.title = 'Choose a picture',
    this.accepts = isPicture,
    this.fileIcon = QuarkIcons.image_outlined,
    this.emptyText = 'No pictures or folders here',
    this.keyPrefix = imageKeyPrefix,
    super.key,
  });

  /// The folder shown first, relative to the files root; empty for the root.
  final String startPath;

  /// Lists the folder at a path.
  final Future<List<FileNode>> Function(String path) listFolder;

  /// The dialog's heading.
  final String title;

  /// Whether a file of this name is listed to pick.
  final bool Function(String name) accepts;

  /// The glyph on each file row, from `QuarkIcons`.
  final IconData fileIcon;

  /// What a folder holding no folders and nothing [accepts] lets through
  /// says.
  final String emptyText;

  /// Where every key in the dialog starts.
  final String keyPrefix;

  /// The key prefix of the picture picker.
  static const imageKeyPrefix = 'slide_quark_image';

  /// Whether [name] is a picture, the default for [accepts].
  static bool isPicture(String name) => fileKindForName(name) == FileKind.image;

  /// Shows the dialog and completes with the chosen path, or null.
  static Future<String?> show(
    BuildContext context, {
    required String startPath,
    required Future<List<FileNode>> Function(String path) listFolder,
    String title = 'Choose a picture',
    bool Function(String name) accepts = isPicture,
    IconData fileIcon = QuarkIcons.image_outlined,
    String emptyText = 'No pictures or folders here',
    String keyPrefix = imageKeyPrefix,
  }) => showDialog<String>(
    context: context,
    builder: (_) => SlideQuarkImageDialog(
      startPath: startPath,
      listFolder: listFolder,
      title: title,
      accepts: accepts,
      fileIcon: fileIcon,
      emptyText: emptyText,
      keyPrefix: keyPrefix,
    ),
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
    final prefix = widget.keyPrefix;
    return AlertDialog(
      key: ValueKey('${prefix}_dialog'),
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                QuarkBarIconButton(
                  key: ValueKey('${prefix}_up'),
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
                            key: ValueKey('${prefix}_retry'),
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
                      if (!n.isDir && widget.accepts(n.name)) n,
                  ];
                  if (entries.isEmpty) {
                    return Center(
                      child: Text(
                        widget.emptyText,
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
                              ? '${prefix}_folder_${node.name}'
                              : '${prefix}_file_${node.name}',
                        ),
                        leading: Icon(
                          node.isDir
                              ? QuarkIcons.folder_outlined
                              : widget.fileIcon,
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
