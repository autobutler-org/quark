import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// What the screen shows while a PowerPoint file uploads and imports
/// (#1171): a loader and the file's [name]. It cannot be dismissed — the
/// import flow closes it once the Quark answers.
///
/// Key prefixes: `slides_import_progress` on the dialog.
class PowerPointImportProgressDialog extends StatelessWidget {
  /// A dialog for importing [name].
  const PowerPointImportProgressDialog({required this.name, super.key});

  /// The PowerPoint file's name, as `Talk.pptx`.
  final String name;

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const ValueKey('slides_import_progress'),
        content: Row(
          children: [
            const QuarkLoader(size: 20),
            SizedBox(width: tokens.spacingMd),
            Expanded(
              child: Text(
                'Importing $name…',
                semanticsLabel: 'Importing $name',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
