import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:quark/controllers/file_browser_controller.dart';
import 'package:quark/models/file_node.dart';
import 'package:quark/services/app_settings.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks which Quark folder an attachment should be saved into.
///
/// The listing starts where the file browser does: an admin at the top of
/// the files, anyone else in their home ([landingPath]). Up stops there.
/// Null means the dialog was dismissed. `/` is the top, and any other path
/// is the folder the person picked.
Future<String?> showChatSaveFolderPicker(
  BuildContext context, {
  String? rootPath,
  Future<List<FileNode>> Function(String path)? listFiles,
}) {
  final root =
      rootPath ??
      landingPath(
        isAdmin: AppSettings.instance.isAdmin.value,
        username: AppSettings.instance.username,
      );
  final list = listFiles ?? (String path) => FilesService.getFiles(path);
  return showDialog<String>(
    context: context,
    builder: (context) => ChatSaveFolderDialog(rootPath: root, listFiles: list),
  );
}

/// The folder picker for [showChatSaveFolderPicker].
///
/// [rootPath] is the file browser's landing path, `''` for the top. Folders
/// come from [listFiles], which is given that same path spelling. Only
/// directories are shown.
class ChatSaveFolderDialog extends StatefulWidget {
  /// Creates a picker rooted at [rootPath].
  const ChatSaveFolderDialog({
    required this.rootPath,
    required this.listFiles,
    super.key,
  });

  /// Where Up stops, in the file browser's spelling. Empty is the top.
  final String rootPath;

  /// Lists [path]. Empty is the top of the files, the same value
  /// [FilesService.getFiles] is given for the file browser's root.
  final Future<List<FileNode>> Function(String path) listFiles;

  @override
  State<ChatSaveFolderDialog> createState() => _ChatSaveFolderDialogState();
}

class _ChatSaveFolderDialogState extends State<ChatSaveFolderDialog> {
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

  /// What the picker prints. The file browser's empty root is `/`.
  String get _shownPath {
    final normalized = normalizePath(_path);
    return normalized.isEmpty ? '/' : normalized;
  }

  String get _shownName {
    if (_atRoot) return 'My files';
    final normalized = normalizePath(_path);
    return normalized.split('/').last;
  }

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
    final path = _browser.nextPathForOpenDirectory(
      currentPath: _path,
      node: node,
    );
    if (normalizePath(path).isEmpty) return null;
    return QuarkFolderEntry(path: normalizePath(path), name: name);
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
      title: const Text('Save to my files'),
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
    );
  }
}
