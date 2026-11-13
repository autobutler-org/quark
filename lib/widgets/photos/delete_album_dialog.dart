import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Confirms deleting an album. Pops with true to delete.
class DeleteAlbumDialog extends StatelessWidget {
  /// Creates the confirmation for the album named [albumName].
  const DeleteAlbumDialog({required this.albumName, super.key});

  /// Shows the dialog and answers whether the user confirmed.
  static Future<bool> show(BuildContext context, {required String albumName}) =>
      showDialog<bool>(
        context: context,
        builder: (_) => DeleteAlbumDialog(albumName: albumName),
      ).then((confirmed) => confirmed ?? false);

  /// The album being deleted, named in the question.
  final String albumName;

  @override
  Widget build(BuildContext context) {
    return ConfirmDeleteDialog(
      title: 'Delete album?',
      body:
          'Delete "$albumName"? Photos will not be deleted from disk. '
          'Sub-albums will also be deleted.',
      keyPrefix: 'delete_album',
      onConfirm: () => Navigator.of(context).pop(true),
      onCancel: () => Navigator.of(context).pop(false),
    );
  }
}
