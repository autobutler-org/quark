import 'package:material_ui/material_ui.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Asks for an album name, for creating or renaming one, in a
/// [QuarkNameDialog].
///
/// Pops with the trimmed name on save or submit, or null on cancel. A name
/// that is empty, contains `/`, or that [isNameTaken] says a sibling already
/// has cannot be saved; the last two say why under the field.
///
/// Keys: the [QuarkNameDialog]'s `name_dialog_field` and `name_dialog_submit`.
class AlbumNameDialog extends StatelessWidget {
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

  /// Why [name] cannot be an album's name, or null when it can.
  String? _problem(String name) {
    if (name.contains('/')) return Errors.albumNameHasSlash;
    if (isNameTaken?.call(name) ?? false) return Errors.albumNameTaken;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return QuarkNameDialog(
      title: title,
      label: 'Album name',
      submitLabel: 'Save',
      initialName: initial,
      validator: _problem,
      onSubmit: (name) => Navigator.of(context).pop(name),
      onCancel: () => Navigator.of(context).pop(),
    );
  }
}
