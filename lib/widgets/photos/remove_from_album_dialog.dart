import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

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
    return ConfirmDeleteDialog(
      title: 'Remove from album?',
      body:
          'This removes the photo from this album. The file on disk is not '
          'affected.',
      keyPrefix: 'remove_from_album',
      confirmLabel: 'Remove',
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
    );
  }
}
