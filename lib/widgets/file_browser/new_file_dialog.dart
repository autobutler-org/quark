import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Shows [NewFileDialog] and returns the chosen filename (with extension), or
/// null if the user cancelled.
///
/// The dialog body lives in `quark_widgets`; popping the route is the app's
/// job, which is all this wrapper does.
///
/// ```dart
/// final name = await showNewFileDialog(context);
/// if (name != null) { /* create the file */ }
/// ```
Future<String?> showNewFileDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => NewFileDialog(
      onCreate: (name) => Navigator.of(ctx).pop(name),
      onCancel: () => Navigator.of(ctx).pop(),
    ),
  );
}
