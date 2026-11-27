import 'package:material_ui/material_ui.dart';

/// What the reader chose when the `.qdoc` a conversion would write is already
/// there.
enum DocumentConvertConflictChoice {
  /// Open the `.qdoc` that is already there and convert nothing.
  openExisting,

  /// Convert again over it.
  replace,
}

/// Asks what to do when "Open as Quark doc" finds its `.qdoc` already there
/// (#3265). Converting again would throw away whatever was done to it, so the
/// reader chooses; the dialog pops with a [DocumentConvertConflictChoice], or
/// null for Cancel.
///
/// Keys: `document_convert_cancel`, `document_convert_replace` and
/// `document_convert_open_existing`.
class DocumentConvertConflictDialog extends StatelessWidget {
  /// The name of the `.qdoc` that is already there.
  final String qdocName;

  /// The name of the document being converted.
  final String sourceName;

  const DocumentConvertConflictDialog({
    required this.qdocName,
    required this.sourceName,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Document already exists'),
      content: Text(
        '"$qdocName" is already here. Open it, or replace it with a fresh '
        'copy of "$sourceName"?',
      ),
      actions: [
        TextButton(
          key: const ValueKey('document_convert_cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const ValueKey('document_convert_replace'),
          onPressed: () =>
              Navigator.of(context).pop(DocumentConvertConflictChoice.replace),
          child: const Text('Replace'),
        ),
        FilledButton(
          key: const ValueKey('document_convert_open_existing'),
          onPressed: () => Navigator.of(
            context,
          ).pop(DocumentConvertConflictChoice.openExisting),
          child: const Text('Open existing'),
        ),
      ],
    );
  }
}
