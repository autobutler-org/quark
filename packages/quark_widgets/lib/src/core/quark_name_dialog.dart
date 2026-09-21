import 'package:flutter/material.dart';

import '../theme/quark_tokens.dart';

/// Asks for one name, to create something or rename it: a title, a text
/// field, and a submit button.
///
/// Generic on purpose. The caller writes the title, the field label and the
/// submit label, so the same dialog names a group or anything else that has
/// a name.
///
/// It does not close itself. [onSubmit] receives the trimmed name, and
/// [onCancel] fires on the cancel button; the caller that pushed the dialog
/// pops it, usually once the Quark has accepted the name. While that request
/// is out the caller passes [isSubmitting], and a refusal comes back in as
/// [error], so the dialog stays open with what was typed.
///
/// The typed text is [State] because it is the form's own transient input,
/// thrown away when the dialog closes. The outcome leaves through [onSubmit].
///
/// Key prefixes: `name_dialog_field`, `name_dialog_cancel`, and
/// `name_dialog_submit`.
///
/// ```dart
/// showDialog<void>(
///   context: context,
///   builder: (ctx) => QuarkNameDialog(
///     title: 'New group',
///     label: 'Group name',
///     submitLabel: 'Create',
///     maxLength: 64,
///     isSubmitting: controller.isSaving,
///     error: saveError,
///     onSubmit: create,
///     onCancel: () => Navigator.of(ctx).pop(),
///   ),
/// );
/// ```
class QuarkNameDialog extends StatefulWidget {
  /// Creates the dialog titled [title].
  const QuarkNameDialog({
    required this.title,
    required this.label,
    required this.submitLabel,
    required this.onSubmit,
    required this.onCancel,
    this.initialName = '',
    this.maxLength,
    this.isSubmitting = false,
    this.error,
    super.key,
  });

  /// What the dialog is for, such as "New group" or "Rename Family".
  final String title;

  /// The text field's label.
  final String label;

  /// The submit button's label, such as "Create" or "Rename".
  final String submitLabel;

  /// Called with the trimmed name when the submit button is tapped or the
  /// keyboard's done key is pressed. Never called with an empty name.
  final ValueChanged<String> onSubmit;

  /// Called when the cancel button is tapped.
  final VoidCallback onCancel;

  /// The name the field starts with, for a rename. Empty for a new name.
  final String initialName;

  /// The most characters the field accepts, shown as a counter under it.
  /// Null sets no limit.
  final int? maxLength;

  /// Whether the name is being saved. Disables both buttons.
  final bool isSubmitting;

  /// A sentence saying why the last attempt was refused, composed by the
  /// caller. Shown under the field.
  final String? error;

  @override
  State<QuarkNameDialog> createState() => _QuarkNameDialogState();
}

class _QuarkNameDialogState extends State<QuarkNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialName,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _name => _controller.text.trim();

  bool get _canSubmit => !widget.isSubmitting && _name.isNotEmpty;

  void _submit() {
    if (_canSubmit) widget.onSubmit(_name);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final error = widget.error;

    return AlertDialog(
      // A long refusal on a small phone scrolls rather than overflowing.
      scrollable: true,
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              key: const ValueKey('name_dialog_field'),
              controller: _controller,
              autofocus: true,
              maxLength: widget.maxLength,
              decoration: InputDecoration(
                labelText: widget.label,
                border: const OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _submit(),
            ),
            if (error != null) ...[
              SizedBox(height: tokens.spacingSm),
              Text(error, style: TextStyle(color: tokens.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const ValueKey('name_dialog_cancel'),
          onPressed: widget.isSubmitting ? null : widget.onCancel,
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('name_dialog_submit'),
          onPressed: _canSubmit ? _submit : null,
          child: widget.isSubmitting
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(widget.submitLabel),
        ),
      ],
    );
  }
}
