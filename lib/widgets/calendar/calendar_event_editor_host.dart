import 'package:flutter/material.dart';
import 'package:quark/controllers/calendar_editor_controller.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The event form wired to its [CalendarEditorController]: the package's
/// [CalendarEventEditor] rebuilt on every change, closing itself once a save
/// or a delete goes through.
///
/// Delete asks first. The form closes on a successful save or delete, and
/// stays open with the error on a failed one.
class CalendarEventEditorHost extends StatelessWidget {
  /// Creates the form for [editor].
  const CalendarEventEditorHost({required this.editor, super.key});

  /// The open form's state.
  final CalendarEditorController editor;

  Future<void> _delete(BuildContext context) async {
    final title = editor.draft.title.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => ConfirmDeleteDialog(
        title: title.isEmpty ? 'Delete this event?' : 'Delete $title?',
        body: editor.editsSeries
            ? 'Every time it repeats is deleted too.'
            : 'It is removed from the calendar for everyone.',
        keyPrefix: 'delete_event',
        onConfirm: () => Navigator.of(ctx).pop(true),
        onCancel: () => Navigator.of(ctx).pop(false),
      ),
    );
    if (confirmed != true) return;
    if (await editor.remove() && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: editor,
      builder: (context, _) => CalendarEventEditor(
        draft: editor.draft,
        isNew: editor.isNew,
        editsSeries: editor.editsSeries,
        isSaving: editor.isSaving,
        timeError: editor.timeError,
        saveError: editor.saveError,
        onChanged: editor.update,
        onSave: editor.canSave
            ? () async {
                if (await editor.submit() && context.mounted) {
                  Navigator.of(context).pop();
                }
              }
            : null,
        onCancel: () => Navigator.of(context).pop(),
        onDelete: editor.isNew ? null : () => _delete(context),
      ),
    );
  }
}
