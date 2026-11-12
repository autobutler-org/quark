import 'package:material_ui/material_ui.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Holds a draft so the poll form can be edited in the gallery, the way a
/// page's controller holds it in the app, and keeps Post off until the draft
/// is complete.
class PollEditorDemo extends StatefulWidget {
  /// Creates the demo, logging each change and action to [log].
  const PollEditorDemo({required this.initial, required this.log, super.key});

  /// The draft the form opens with.
  final ChatPollDraft initial;

  /// The gallery's event log.
  final void Function(String event) log;

  @override
  State<PollEditorDemo> createState() => _PollEditorDemoState();
}

class _PollEditorDemoState extends State<PollEditorDemo> {
  late ChatPollDraft _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    return QuarkPollEditor(
      draft: _draft,
      onChanged: (draft) {
        widget.log(
          'QuarkPollEditor.onChanged ${draft.type.name} ${draft.prompt} '
          '${draft.options}',
        );
        setState(() => _draft = draft);
      },
      onSave: _draft.isComplete
          ? () => widget.log('QuarkPollEditor.onSave')
          : null,
      onCancel: () => widget.log('QuarkPollEditor.onCancel'),
    );
  }
}
