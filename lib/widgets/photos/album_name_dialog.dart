import 'package:flutter/material.dart';

/// Asks for an album name, for creating or renaming one.
///
/// Pops with the trimmed name on save or submit, or null on cancel.
class AlbumNameDialog extends StatefulWidget {
  /// Creates the dialog titled [title], starting from [initial].
  const AlbumNameDialog({required this.title, this.initial = '', super.key});

  /// Shows the dialog and answers with the name, or null when canceled.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    String initial = '',
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => AlbumNameDialog(title: title, initial: initial),
    );
  }

  /// What the dialog is for: "New album", "Rename album".
  final String title;

  /// The name the field starts with.
  final String initial;

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

  void _save() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Album name'),
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
