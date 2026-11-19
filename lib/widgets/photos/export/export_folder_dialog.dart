import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks which folder on one drive a photo export goes into (#3501), with the
/// package's [QuarkFolderPicker], the way the chat's save picker does.
///
/// [rootPath] is where Up stops, in the file browser's spelling: `''` for the
/// top of the drive. Folders come from [listFiles], already bound to the
/// drive. The dialog pops the chosen folder, `/` for the top, or null when
/// dismissed.
class ExportFolderDialog extends StatefulWidget {
  /// Creates a picker on [driveName], rooted at [rootPath].
  const ExportFolderDialog({
    required this.driveName,
    required this.rootPath,
    required this.listFiles,
    super.key,
  });

  /// The drive's name, for the title and the top folder's name.
  final String driveName;

  /// Where Up stops. Empty is the top of the drive.
  final String rootPath;

  /// Lists a folder on the drive.
  final Future<List<FileNode>> Function(String path) listFiles;

  /// Shows the dialog and answers the chosen folder, or null.
  static Future<String?> show(
    BuildContext context, {
    required String driveName,
    required String rootPath,
    required Future<List<FileNode>> Function(String path) listFiles,
  }) => showDialog<String>(
    context: context,
    builder: (context) => ExportFolderDialog(
      driveName: driveName,
      rootPath: rootPath,
      listFiles: listFiles,
    ),
  );

  @override
  State<ExportFolderDialog> createState() => _ExportFolderDialogState();
}

class _ExportFolderDialogState extends State<ExportFolderDialog> {
  static const _browser = FileBrowserController();

  late final String _root = normalizePath(widget.rootPath);
  late String _path = _root;
  var _loading = true;
  String? _error;
  List<QuarkFolderEntry> _folders = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_fetch());
  }

  bool get _atRoot => normalizePath(_path) == _root;

  String get _shownPath {
    final normalized = normalizePath(_path);
    return normalized.isEmpty ? '/' : normalized;
  }

  String get _shownName =>
      _atRoot && _root.isEmpty ? widget.driveName : _shownPath.split('/').last;

  Future<void> _open(String path) async {
    setState(() {
      _path = normalizePath(path);
      _loading = true;
      _error = null;
      _folders = const [];
    });
    await _fetch();
  }

  Future<void> _fetch() async {
    try {
      final nodes = await widget.listFiles(_path);
      if (!mounted) return;
      setState(() {
        _folders = [
          for (final node in nodes)
            if (node.isDir) _entry(node),
        ].whereType<QuarkFolderEntry>().toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = Errors.message(error, 'load the folder');
      });
    }
  }

  QuarkFolderEntry? _entry(FileNode node) {
    final name = trimTrailingSlashes(node.name);
    if (name.isEmpty || name == '.' || name == '..') return null;
    final path = normalizePath(
      _browser.nextPathForOpenDirectory(currentPath: _path, node: node),
    );
    if (path.isEmpty) return null;
    return QuarkFolderEntry(path: path, name: name);
  }

  void _up() {
    if (_atRoot) return;
    final parent = _browser.nextPathForGoUp(_path);
    if (!isWithin(_root, parent)) return;
    unawaited(_open(parent));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Choose a folder on ${widget.driveName}'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: QuarkFolderPicker(
          folders: _folders,
          currentPath: _shownPath,
          currentName: _shownName,
          canGoUp: !_atRoot,
          isLoading: _loading,
          error: _error,
          onOpen: (folder) => unawaited(_open(folder.path)),
          onUp: _up,
          onSelect: () => Navigator.of(context).pop(_shownPath),
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
