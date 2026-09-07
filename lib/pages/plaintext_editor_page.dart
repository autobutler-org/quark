import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:quark/router.dart';
import 'package:quark/services/files_service.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark/utils/file_browser_path_utils.dart';
import 'package:quark/widgets/layout/theme_toggle_button.dart';
import 'package:quark/widgets/plaintext_editor/plaintext_editor_body.dart';

/// A simple plaintext editor for text-like files (txt, md, json, yaml, etc.)
class PlaintextEditorPage extends StatefulWidget {
  final String filePath;
  final String deviceSerial;

  const PlaintextEditorPage({
    required this.filePath,
    this.deviceSerial = '',
    super.key,
  });

  @override
  State<PlaintextEditorPage> createState() => _PlaintextEditorPageState();
}

class _PlaintextEditorPageState extends State<PlaintextEditorPage> {
  final TextEditingController _textController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;

  /// The thrown object, not its message — the render decides whether it means
  /// "your Quark is unreachable" or "the request failed" (#1637).
  Object? _error;

  late String _displayName;

  @override
  void initState() {
    super.initState();
    _displayName = widget.filePath.split('/').last;
    _textController.addListener(_onTextChanged);
    _loadFile();
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (!_dirty && mounted) {
      setState(() => _dirty = true);
    }
  }

  Future<void> _loadFile() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final serial = serialOrNull(widget.deviceSerial);
      final bytes = await FilesService.downloadFileBytes(
        widget.filePath,
        serial: serial,
      );
      if (!mounted) return;
      final text = bytes != null && bytes.isNotEmpty
          ? utf8.decode(bytes, allowMalformed: true)
          : '';
      _textController.removeListener(_onTextChanged);
      _textController.text = text;
      _textController.addListener(_onTextChanged);
      setState(() {
        _loading = false;
        _dirty = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  Future<void> _saveFile() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = utf8.encode(_textController.text);
      final fileName = _displayName;
      final parentDir = parentPath(widget.filePath);
      final serial = serialOrNull(widget.deviceSerial);
      final file = http.MultipartFile.fromBytes(
        'files',
        bytes,
        filename: fileName,
      );
      await FilesService.uploadFilesFromFormData(
        parentDir,
        [file],
        serial: serial,
        overwrite: true,
      );
      if (!mounted) return;
      setState(() {
        _saving = false;
        _dirty = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved')));
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(Errors.message(e, 'save the file'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _dirty ? '$_displayName •' : _displayName;

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            // Nothing underneath — a deep link, or a pasted URL. The home
            // folder is not where this file lives (#1749).
            context.go(AppRoutes.containingFolder(widget.filePath));
          },
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save',
              onPressed: _dirty ? _saveFile : null,
            ),
          const AppThemeToggle(),
        ],
      ),
      body: PlaintextEditorBody(
        loading: _loading,
        error: _error,
        onRetry: _loadFile,
        controller: _textController,
      ),
    );
  }
}
