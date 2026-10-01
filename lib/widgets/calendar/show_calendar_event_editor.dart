import 'package:flutter/material.dart';
import 'package:quark/controllers/calendar_controller.dart';
import 'package:quark/controllers/calendar_editor_controller.dart';
import 'package:quark/widgets/calendar/calendar_event_editor_host.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// Opens the event form over the calendar: a bottom sheet on a phone, a
/// dialog on a wider screen (#2490). It opens on [draft], editing event
/// [eventId] or creating one when that is null, and saves and deletes through
/// [calendar]. It completes when the form closes.
Future<void> showCalendarEventEditor(
  BuildContext context, {
  required CalendarController calendar,
  required CalendarEventDraft draft,
  int? eventId,
}) async {
  final editor = CalendarEditorController(
    draft: draft,
    eventId: eventId,
    save: calendar.save,
    delete: calendar.delete,
  );
  final compact =
      MediaQuery.sizeOf(context).width < QuarkBarChip.compactBreakpoint;
  try {
    if (compact) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => Padding(
          // The keyboard pushes the form up rather than covering Save.
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
          child: FractionallySizedBox(
            heightFactor: 0.92,
            child: CalendarEventEditorHost(editor: editor),
          ),
        ),
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 760),
            child: CalendarEventEditorHost(editor: editor),
          ),
        ),
      );
    }
  } finally {
    editor.dispose();
  }
}
