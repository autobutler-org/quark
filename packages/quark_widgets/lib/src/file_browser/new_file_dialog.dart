import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../theme/quark_tokens.dart';
import 'new_file_dialog/new_file_type_card.dart';

/// A creatable file type offered by [NewFileDialog].
@immutable
class NewFileType {
  /// Creates a type shown as [label] under [icon], creating files ending in
  /// [extension].
  const NewFileType({
    required this.label,
    required this.extension,
    required this.icon,
  });

  /// The name shown on the type card.
  final String label;

  /// The suffix appended to the typed name, leading dot included. Empty means
  /// the user types the whole filename, extension and all.
  final String extension;

  /// The glyph on the type card.
  final IconData icon;

  /// Placeholder for the name field while it is empty.
  ///
  /// `.qsheet` hints `Untitled spreadsheet` and an empty [extension] hints
  /// `filename.txt`. Every other extension, including `.qdoc`, hints
  /// `Untitled document`.
  String get nameHint => switch (extension) {
    '.qsheet' => 'Untitled spreadsheet',
    '' => 'filename.txt',
    _ => 'Untitled document',
  };
}

/// The file types the dialog offers by default.
const List<NewFileType> kNewFileTypes = [
  NewFileType(
    label: 'Document',
    extension: '.qdoc',
    icon: QuarkIcons.edit_document,
  ),
  NewFileType(
    label: 'Spreadsheet',
    extension: '.qsheet',
    icon: QuarkIcons.table_chart,
  ),
  NewFileType(
    label: 'Generic File',
    extension: '',
    icon: Icons.insert_drive_file_outlined,
  ),
];

/// The body of the new-file dialog: a type picker and a validated name field.
///
/// It does not close itself. [onCreate] receives the finished filename with
/// the chosen extension already appended, and [onCancel] fires on the cancel
/// button; the caller that pushed the dialog is the one that pops it.
///
/// The selected type and the typed name are [State] because they are a form's
/// own transient input, thrown away the moment the dialog closes. Nothing
/// outside the dialog can observe them, and the one outcome that matters
/// leaves through [onCreate].
///
/// Key prefixes: `new_file_type_<extension without the dot, or `generic`>`,
/// `new_file_name`, `new_file_cancel`, and `new_file_create`.
///
/// ```dart
/// showDialog<String>(
///   context: context,
///   builder: (ctx) => NewFileDialog(
///     onCreate: (name) => Navigator.of(ctx).pop(name),
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class NewFileDialog extends StatefulWidget {
  /// Creates the dialog body offering [types].
  const NewFileDialog({
    required this.onCreate,
    required this.onCancel,
    this.types = kNewFileTypes,
    super.key,
  });

  /// Called with the full filename once the name validates. The extension of
  /// the selected type is already appended.
  final ValueChanged<String> onCreate;

  /// Called when the user dismisses the dialog through its cancel button.
  final VoidCallback onCancel;

  /// The types on offer. Must not be empty; the first is selected initially.
  final List<NewFileType> types;

  @override
  State<NewFileDialog> createState() => _NewFileDialogState();
}

class _NewFileDialogState extends State<NewFileDialog> {
  late NewFileType _selected = widget.types.first;
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String? _validateName(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Name cannot be empty';
    if (v.contains('/') || v.contains('\\')) {
      return 'Name cannot contain slashes';
    }
    if (v.contains('\x00')) return 'Name contains invalid characters';
    return null;
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final name = _nameController.text.trim();
    // For generic files the extension is empty, so the name goes out as typed.
    widget.onCreate('$name${_selected.extension}');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tokens = QuarkTokens.of(context);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: colorScheme.onSurface.withValues(alpha: 0.5),
    );

    return AlertDialog(
      title: const Text('New file'),
      contentPadding: EdgeInsets.fromLTRB(
        tokens.spacingLg,
        tokens.spacingMd,
        tokens.spacingLg,
        0,
      ),
      content: SizedBox(
        width: 360,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File type', style: labelStyle),
              SizedBox(height: tokens.spacingSm),
              Wrap(
                spacing: tokens.spacingSm,
                runSpacing: tokens.spacingSm,
                children: [
                  for (final type in widget.types)
                    NewFileTypeCard(
                      type: type,
                      isSelected: type == _selected,
                      onTap: () => setState(() => _selected = type),
                    ),
                ],
              ),
              SizedBox(height: tokens.spacingMd + tokens.spacingXs),
              Text('Name', style: labelStyle),
              SizedBox(height: tokens.spacingSm),
              TextFormField(
                key: const ValueKey('new_file_name'),
                controller: _nameController,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: _selected.nameHint,
                  suffixText: _selected.extension.isEmpty
                      ? null
                      : _selected.extension,
                  border: const OutlineInputBorder(),
                ),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                validator: _validateName,
              ),
              SizedBox(height: tokens.spacingXs),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('new_file_cancel'),
          onPressed: widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('new_file_create'),
          onPressed: _submit,
          child: const Text('Create'),
        ),
      ],
    );
  }
}
