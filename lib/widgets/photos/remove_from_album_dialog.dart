import 'package:flutter/material.dart';

/// Confirms taking a photo out of an album. Pops with true to remove.
class RemoveFromAlbumDialog extends StatelessWidget {
  /// Creates the confirmation.
  const RemoveFromAlbumDialog({super.key});

  /// Shows the dialog and answers whether the user confirmed.
  static Future<bool> show(BuildContext context) => showDialog<bool>(
    context: context,
    builder: (_) => const RemoveFromAlbumDialog(),
  ).then((confirmed) => confirmed ?? false);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Remove from album?'),
      content: const Text(
        'This removes the photo from this album. The file on disk is not '
        'affected.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Remove'),
        ),
      ],
    );
  }
}
