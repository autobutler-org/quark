import 'package:flutter/material.dart';
import 'package:quark/utils/error_text.dart';

/// Asks for an album name, for creating or renaming one.
///
/// Pops with the trimmed name on save or submit, or null on cancel. A name
/// that is empty, contains `/`, or that [isNameTaken] says a sibling already
/// has cannot be saved; the last two say why under the field.
///
/// Keys: `album_name_field`, `album_name_save`.
class AlbumNameDialog extends StatefulWidget {
  /// Creates the dialog titled [title], starting from [initial].
  const AlbumNameDialog({
    required this.title,
    this.initial = '',
    this.isNameTaken,
    super.key,
  });

  /// Shows the dialog and answers with the name, or null when canceled.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initial = '',
    bool Function(String name)? isNameTaken,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AlbumNameDialog(
        title: title,
        initial: initial,
        isNameTaken: isNameTaken,
      ),
    );
  }

  /// What the dialog is for: "New album", "Rename album".
  final String title;

  /// The name the field starts with.
  final String initial;

  /// Whether another album beside this one already has the trimmed name.
  /// Null checks nothing, leaving the Quark's 409 to catch a clash.
  final bool Function(String name)? isNameTaken;

  @override
  State<AlbumNameDialog> createState() => _AlbumNameDialogState();
}

class _AlbumNameDialogState extends State<AlbumNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  /// Why [_name] cannot be saved, or null when it can (or is just empty).
  String? get _problem {
    if (_name.contains('/')) return Errors.albumNameHasSlash;
    if (widget.isNameTaken?.call(_name) ?? false) return Errors.albumNameTaken;
    return null;
  }

  bool get _canSave => _name.isNotEmpty && _problem == null;

  void _save() {
    if (_canSave) Navigator.of(context).pop(_name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('album_name_field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          hintText: 'Album name',
          errorText: _problem,
        ),
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('album_name_save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
