import 'package:flutter/material.dart';
import 'package:quark_icons/quark_icons.dart';

import '../core/quark_loader.dart';
import '../models/calendar_event_draft.dart';
import '../models/calendar_repeat.dart';
import '../theme/quark_tokens.dart';
import 'calendar_event_editor/editor_field_row.dart';
import 'calendar_event_editor/editor_picker_button.dart';
import 'calendar_event_editor/event_color_picker.dart';
import 'calendar_event_editor/reminder_picker.dart';
import 'calendar_event_editor/repeat_end_picker.dart';
import 'calendar_event_editor/repeat_preset_picker.dart';
import 'calendar_dates.dart';
import 'calendar_labels.dart';

/// The one form for creating and editing a calendar event: title, all day,
/// start and end, repeat and when it stops, reminder, color, location and
/// notes, with Save, Cancel and (for a saved event) Delete.
///
/// It edits nothing itself. Every change comes back through [onChanged] as a
/// new [CalendarEventDraft] and the caller hands the next draft in. The caller
/// validates, too: it passes a null [onSave] until the draft can be saved,
/// which disables Save, and [timeError], [repeatError] and [saveError] are
/// sentences it composed, shown under their fields. Date and time fields open the platform
/// pickers. It lays itself out for its width: labels beside fields in a
/// desktop dialog, above them in a phone's bottom sheet. It is only the form,
/// so the caller shows it in whichever of the two fits. Its body scrolls, so
/// give it a bounded height.
///
/// Key prefixes: `event_title`, `event_all_day`, `event_start_date`,
/// `event_start_time`, `event_end_date`, `event_end_time`,
/// `event_repeat_<preset>`, `event_repeat_ends_never`, `event_repeat_ends_on`,
/// `event_repeat_until`, `event_remind_<minutes|off>`,
/// `event_color_<index>`, `event_location`, `event_notes`, `event_save`,
/// `event_cancel`, `event_delete` and `event_close`.
///
/// ```dart
/// CalendarEventEditor(
///   draft: draft.value,
///   isNew: true,
///   onChanged: (next) => draft.value = next,
///   onSave: draft.value.title.trim().isEmpty ? null : save,
///   onCancel: () => Navigator.pop(context),
/// );
/// ```
class CalendarEventEditor extends StatefulWidget {
  /// Creates the form around [draft].
  const CalendarEventEditor({
    required this.draft,
    required this.onChanged,
    required this.onCancel,
    this.onSave,
    this.onDelete,
    this.isNew = true,
    this.editsSeries = false,
    this.isSaving = false,
    this.timeError,
    this.repeatError,
    this.saveError,
    super.key,
  });

  /// The event as it stands.
  final CalendarEventDraft draft;

  /// Called with the draft after every change.
  final ValueChanged<CalendarEventDraft> onChanged;

  /// Called by Save. Null disables Save, as for a draft that is missing a
  /// title or ends before it starts.
  final VoidCallback? onSave;

  /// Called by Cancel and by the close button.
  final VoidCallback onCancel;

  /// Called by Delete. Null hides it, as for an event not yet saved.
  final VoidCallback? onDelete;

  /// Whether this creates an event: titles the form "New event" and focuses
  /// the title.
  final bool isNew;

  /// Whether this edits a saved repeating event, whose changes reach every
  /// occurrence.
  final bool editsSeries;

  /// Whether a save is in flight: the buttons wait and Save shows a loader.
  final bool isSaving;

  /// The caller's sentence about the start and end, or null.
  final String? timeError;

  /// The caller's sentence about when the repeat stops, or null.
  final String? repeatError;

  /// The caller's sentence about a failed save or delete, or null.
  final String? saveError;

  /// At this width and above the labels sit beside their fields.
  static const double wideWidth = 440;

  @override
  State<CalendarEventEditor> createState() => _CalendarEventEditorState();
}

class _CalendarEventEditorState extends State<CalendarEventEditor> {
  late final TextEditingController _title = TextEditingController(
    text: widget.draft.title,
  );
  late final TextEditingController _location = TextEditingController(
    text: widget.draft.location,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.draft.notes,
  );

  @override
  void didUpdateWidget(CalendarEventEditor old) {
    super.didUpdateWidget(old);
    // Follow a draft the caller replaced, without moving the cursor on the
    // echo of what was just typed.
    if (_title.text != widget.draft.title) _title.text = widget.draft.title;
    if (_location.text != widget.draft.location) {
      _location.text = widget.draft.location;
    }
    if (_notes.text != widget.draft.notes) _notes.text = widget.draft.notes;
  }

  @override
  void dispose() {
    _title.dispose();
    _location.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pickDate(DateTime initial, bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 50),
      lastDate: DateTime(initial.year + 50),
    );
    if (picked == null || !mounted) return;
    final draft = widget.draft;
    widget.onChanged(
      start ? draft.withStartDate(picked) : draft.withEndDate(picked),
    );
  }

  Future<void> _pickRepeatUntil(DateTime initial) async {
    final first = widget.draft.start;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(first) ? first : initial,
      firstDate: CalendarDates.dateOnly(first),
      lastDate: DateTime(first.year + 50),
    );
    if (picked == null || !mounted) return;
    widget.onChanged(widget.draft.copyWith(repeatUntil: picked));
  }

  Future<void> _pickTime(DateTime initial, bool start) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (picked == null || !mounted) return;
    final draft = widget.draft;
    widget.onChanged(
      start
          ? draft.withStartTime(picked.hour, picked.minute)
          : draft.withEndTime(picked.hour, picked.minute),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = QuarkTokens.of(context);
    final draft = widget.draft;
    final use24Hour = MediaQuery.alwaysUse24HourFormatOf(context);
    final busy = widget.isSaving;
    final errorStyle = TextStyle(fontSize: 12, color: tokens.error);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= CalendarEventEditor.wideWidth;
        final gap = wide ? 10.0 : 14.0;
        final side = wide ? tokens.spacingLg : 20.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(side, 8, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(
                        widget.isNew ? 'New event' : 'Edit event',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: tokens.foreground,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    key: const ValueKey('event_close'),
                    tooltip: 'Close',
                    onPressed: busy ? null : widget.onCancel,
                    icon: const Icon(QuarkIcons.close_rounded),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(side, 4, side, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: gap,
                  children: [
                    TextField(
                      key: const ValueKey('event_title'),
                      controller: _title,
                      autofocus: widget.isNew,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: tokens.foreground,
                      ),
                      decoration: const InputDecoration(
                        hintText: 'Add a title',
                      ),
                      onChanged: (title) =>
                          widget.onChanged(draft.copyWith(title: title)),
                    ),
                    EditorFieldRow(
                      label: 'All day',
                      icon: QuarkIcons.schedule_rounded,
                      wide: wide,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        // The row's label is drawn beside the switch, not
                        // read with it, so the switch carries its own (#2603).
                        child: MergeSemantics(
                          child: Semantics(
                            label: 'All day',
                            child: Switch(
                              key: const ValueKey('event_all_day'),
                              value: draft.allDay,
                              onChanged: (on) =>
                                  widget.onChanged(draft.withAllDay(on)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    EditorFieldRow(
                      label: 'Starts',
                      wide: wide,
                      child: Row(
                        spacing: 8,
                        children: [
                          Expanded(
                            flex: 4,
                            child: EditorPickerButton(
                              key: const ValueKey('event_start_date'),
                              value: wide
                                  ? CalendarLabels.date(draft.start)
                                  : CalendarLabels.dayTitleShort(draft.start),
                              semanticLabel: 'Start date',
                              onPressed: () => _pickDate(draft.start, true),
                            ),
                          ),
                          if (!draft.allDay)
                            Expanded(
                              flex: 3,
                              child: EditorPickerButton(
                                key: const ValueKey('event_start_time'),
                                value: CalendarLabels.time(
                                  draft.start,
                                  use24Hour: use24Hour,
                                ),
                                semanticLabel: 'Start time',
                                onPressed: () => _pickTime(draft.start, true),
                              ),
                            ),
                        ],
                      ),
                    ),
                    EditorFieldRow(
                      label: 'Ends',
                      wide: wide,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        spacing: 6,
                        children: [
                          Row(
                            spacing: 8,
                            children: [
                              Expanded(
                                flex: 4,
                                child: EditorPickerButton(
                                  key: const ValueKey('event_end_date'),
                                  value: wide
                                      ? CalendarLabels.date(draft.lastDate)
                                      : CalendarLabels.dayTitleShort(
                                          draft.lastDate,
                                        ),
                                  semanticLabel: 'End date',
                                  invalid: widget.timeError != null,
                                  onPressed: () =>
                                      _pickDate(draft.lastDate, false),
                                ),
                              ),
                              if (!draft.allDay)
                                Expanded(
                                  flex: 3,
                                  child: EditorPickerButton(
                                    key: const ValueKey('event_end_time'),
                                    value: CalendarLabels.time(
                                      draft.end,
                                      use24Hour: use24Hour,
                                    ),
                                    semanticLabel: 'End time',
                                    invalid: widget.timeError != null,
                                    onPressed: () =>
                                        _pickTime(draft.end, false),
                                  ),
                                ),
                            ],
                          ),
                          if (widget.timeError != null)
                            Text(widget.timeError!, style: errorStyle),
                        ],
                      ),
                    ),
                    EditorFieldRow(
                      label: 'Repeat',
                      icon: QuarkIcons.event_repeat_outlined,
                      wide: wide,
                      alignTop: true,
                      child: RepeatPresetPicker(
                        value: draft.repeat,
                        start: draft.start,
                        until: draft.savedRepeatUntil,
                        editsSeries: widget.editsSeries,
                        onChanged: (repeat) =>
                            widget.onChanged(draft.copyWith(repeat: repeat)),
                      ),
                    ),
                    if (draft.repeat != CalendarRepeat.none)
                      EditorFieldRow(
                        label: 'Repeat ends',
                        wide: wide,
                        alignTop: true,
                        child: RepeatEndPicker(
                          value: draft.repeatUntil,
                          wide: wide,
                          error: widget.repeatError,
                          // On a date starts a month after the first
                          // occurrence, a date the field then changes.
                          onEndsChanged: (ends) => widget.onChanged(
                            ends
                                ? draft.copyWith(
                                    repeatUntil: DateTime(
                                      draft.start.year,
                                      draft.start.month + 1,
                                      draft.start.day,
                                    ),
                                  )
                                : draft.copyWith(clearRepeatUntil: true),
                          ),
                          onPickDate: () => _pickRepeatUntil(
                            draft.repeatUntil ?? draft.start,
                          ),
                        ),
                      ),
                    EditorFieldRow(
                      label: 'Remind me',
                      icon: QuarkIcons.notifications_outlined,
                      wide: wide,
                      alignTop: true,
                      child: ReminderPicker(
                        value: draft.reminderMinutes,
                        allDay: draft.allDay,
                        onChanged: (minutes) => widget.onChanged(
                          minutes == null
                              ? draft.copyWith(clearReminder: true)
                              : draft.copyWith(reminderMinutes: minutes),
                        ),
                      ),
                    ),
                    EditorFieldRow(
                      label: 'Color',
                      icon: QuarkIcons.palette_outlined,
                      wide: wide,
                      child: EventColorPicker(
                        value: draft.colorIndex,
                        onChanged: (index) =>
                            widget.onChanged(draft.copyWith(colorIndex: index)),
                      ),
                    ),
                    EditorFieldRow(
                      label: 'Location',
                      icon: QuarkIcons.location_on_outlined,
                      wide: wide,
                      child: TextField(
                        key: const ValueKey('event_location'),
                        controller: _location,
                        decoration: const InputDecoration(
                          hintText: 'Add a location',
                          isDense: true,
                        ),
                        onChanged: (location) => widget.onChanged(
                          draft.copyWith(location: location),
                        ),
                      ),
                    ),
                    EditorFieldRow(
                      label: 'Notes',
                      icon: QuarkIcons.notes_rounded,
                      wide: wide,
                      alignTop: true,
                      child: TextField(
                        key: const ValueKey('event_notes'),
                        controller: _notes,
                        minLines: 2,
                        maxLines: 5,
                        decoration: const InputDecoration(
                          hintText: 'Add notes',
                          isDense: true,
                        ),
                        onChanged: (notes) =>
                            widget.onChanged(draft.copyWith(notes: notes)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(side - 8, 12, side, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    spacing: 8,
                    children: [
                      if (widget.saveError != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            widget.saveError!,
                            style: errorStyle.copyWith(fontSize: 13),
                          ),
                        ),
                      Row(
                        spacing: 8,
                        children: [
                          if (widget.onDelete != null && wide)
                            TextButton.icon(
                              key: const ValueKey('event_delete'),
                              onPressed: busy ? null : widget.onDelete,
                              style: TextButton.styleFrom(
                                foregroundColor: tokens.error,
                              ),
                              icon: const Icon(
                                QuarkIcons.delete_outline,
                                size: 18,
                              ),
                              label: const Text('Delete'),
                            ),
                          // A phone's row has no room for three labeled
                          // buttons: Delete keeps its glyph and tooltip.
                          if (widget.onDelete != null && !wide)
                            IconButton(
                              key: const ValueKey('event_delete'),
                              tooltip: 'Delete event',
                              onPressed: busy ? null : widget.onDelete,
                              color: tokens.error,
                              icon: const Icon(QuarkIcons.delete_outline),
                            ),
                          if (wide) const Spacer(),
                          if (wide)
                            OutlinedButton(
                              key: const ValueKey('event_cancel'),
                              onPressed: busy ? null : widget.onCancel,
                              child: const Text('Cancel'),
                            )
                          else
                            Expanded(
                              child: OutlinedButton(
                                key: const ValueKey('event_cancel'),
                                onPressed: busy ? null : widget.onCancel,
                                child: const Text('Cancel'),
                              ),
                            ),
                          if (wide)
                            FilledButton(
                              key: const ValueKey('event_save'),
                              onPressed: busy ? null : widget.onSave,
                              child: busy
                                  ? const QuarkLoader(size: 18)
                                  : const Text('Save'),
                            )
                          else
                            Expanded(
                              child: FilledButton(
                                key: const ValueKey('event_save'),
                                onPressed: busy ? null : widget.onSave,
                                child: busy
                                    ? const QuarkLoader(size: 18)
                                    : const Text('Save'),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
