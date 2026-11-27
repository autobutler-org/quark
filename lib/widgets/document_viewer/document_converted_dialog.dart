import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Says what "Open as Quark doc" left out of the `.qdoc` it wrote, and offers
/// to open it (#3265). Shown only when there is something to say; the dialog
/// pops with true for Open.
///
/// Keys: `document_converted_later` and `document_converted_open`.
class DocumentConvertedDialog extends StatelessWidget {
  /// The name of the `.qdoc` that was written.
  final String qdocName;

  /// What the `.qdoc` does not hold, in the Quark's own sentences.
  final List<String> warnings;

  /// Whether the document was too long to convert whole.
  final bool truncated;

  const DocumentConvertedDialog({
    required this.qdocName,
    required this.warnings,
    this.truncated = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return AlertDialog(
      title: Text('Saved as "$qdocName"'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: tokens.spacingSm,
          children: [
            const Text(
              'The original is untouched. Some of it did not carry over:',
            ),
            if (truncated)
              const Text(
                '• The document was too long to convert in full, so the copy '
                'holds only its beginning.',
              ),
            for (final warning in warnings) Text('• $warning'),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('document_converted_later'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        FilledButton(
          key: const ValueKey('document_converted_open'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Open'),
        ),
      ],
    );
  }
}
