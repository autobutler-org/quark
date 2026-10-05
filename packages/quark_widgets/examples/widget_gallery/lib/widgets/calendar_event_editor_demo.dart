import 'package:flutter/material.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Holds a draft so the event form can be edited in the gallery, the way a
/// page's controller holds it in the app, flags an end before the start, and
/// keeps Save off until the draft has a title and ends after it starts.
class CalendarEventEditorDemo extends StatefulWidget {
  /// Creates the demo, logging each change and action to [log].
  const CalendarEventEditorDemo({
    required this.initial,
    required this.log,
    this.isNew = false,
    super.key,
  });

  /// The draft the form opens with.
  final CalendarEventDraft initial;

  /// The gallery's event log.
  final void Function(String event) log;

  /// Whether the form creates an event rather than editing one.
  final bool isNew;

  @override
  State<CalendarEventEditorDemo> createState() =>
      _CalendarEventEditorDemoState();
}

class _CalendarEventEditorDemoState extends State<CalendarEventEditorDemo> {
  late CalendarEventDraft _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    return CalendarEventEditor(
      draft: _draft,
      isNew: widget.isNew,
      editsSeries: !widget.isNew && _draft.repeat != CalendarRepeat.none,
      timeError: _draft.endsAfterStart
          ? null
          : 'The event has to end after it starts.',
      repeatError: _draft.repeatEndsInTime
          ? null
          : "The repeat can't end before the event starts.",
      onChanged: (draft) {
        widget.log(
          'onChanged ${draft.title} ${draft.start}–${draft.end}'
          ' until ${draft.savedRepeatUntil}',
        );
        setState(() => _draft = draft);
      },
      onSave:
          _draft.title.trim().isEmpty ||
              !_draft.endsAfterStart ||
              !_draft.repeatEndsInTime
          ? null
          : () => widget.log('onSave'),
      onCancel: () => widget.log('onCancel'),
      onDelete: widget.isNew ? null : () => widget.log('onDelete'),
    );
  }
}
