import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/calendar_editor_controller.dart';
import 'package:quark/utils/error_text.dart';
import 'package:quark_widgets/quark_widgets.dart';

/// The open event form: its checks, its saves and deletes, and their errors.
void main() {
  final draft = CalendarEventDraft.at(DateTime(2026, 9, 17, 16));

  CalendarEditorController editor({
    int? eventId,
    CalendarEventDraft? start,
    Object? failWith,
    List<(CalendarEventDraft, int?)>? saved,
    List<int>? deleted,
  }) => CalendarEditorController(
    draft: start ?? draft,
    eventId: eventId,
    save: (d, {id}) async {
      if (failWith != null) throw failWith;
      saved?.add((d, id));
    },
    delete: (id) async {
      if (failWith != null) throw failWith;
      deleted?.add(id);
    },
  );

  test('Save waits for a title and an end after the start', () async {
    final saved = <(CalendarEventDraft, int?)>[];
    final e = editor(saved: saved);
    expect(e.canSave, isFalse);
    expect(await e.submit(), isFalse);
    e.update(draft.copyWith(title: '  '));
    expect(e.canSave, isFalse);
    e.update(draft.copyWith(title: 'Piano'));
    expect(e.canSave, isTrue);
    e.update(e.draft.withEndTime(15, 0));
    expect(e.canSave, isFalse);
    expect(saved, isEmpty);
  });

  test('an end before the start is flagged at once', () {
    final e = editor();
    e.update(draft.withEndTime(15, 0));
    expect(e.timeError, Errors.calendarEndBeforeStart);
  });

  test('saves a new event, then an edit over its id', () async {
    final saved = <(CalendarEventDraft, int?)>[];
    final created = editor(saved: saved)
      ..update(draft.copyWith(title: 'Piano'));
    expect(await created.submit(), isTrue);
    expect(created.isNew, isTrue);

    final edited = editor(eventId: 7, saved: saved)
      ..update(draft.copyWith(title: 'Piano lesson'));
    expect(await edited.submit(), isTrue);
    expect(saved.map((s) => s.$2), [null, 7]);
    expect(saved.last.$1.title, 'Piano lesson');
  });

  test('a failed save is worded and keeps the form open', () async {
    final e = editor(failWith: Exception('save failed'))
      ..update(draft.copyWith(title: 'Piano'));
    expect(await e.submit(), isFalse);
    expect(e.saveError, "Couldn't save the event.");
    expect(e.isSaving, isFalse);
    e.update(e.draft.copyWith(title: 'Piano!'));
    expect(e.saveError, isNull);
  });

  test('deletes only a saved event', () async {
    final deleted = <int>[];
    expect(await editor(deleted: deleted).remove(), isFalse);
    expect(await editor(eventId: 7, deleted: deleted).remove(), isTrue);
    expect(deleted, [7]);
    final failing = editor(eventId: 7, failWith: Exception('delete failed'));
    expect(await failing.remove(), isFalse);
    expect(failing.saveError, "Couldn't delete the event.");
  });

  test('knows when an edit reaches a whole series', () {
    final weekly = draft.copyWith(repeat: CalendarRepeat.weekly);
    expect(editor(eventId: 7, start: weekly).editsSeries, isTrue);
    expect(editor(start: weekly).editsSeries, isFalse);
    expect(editor(eventId: 7).editsSeries, isFalse);
  });
}
