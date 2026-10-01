import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quark_widgets/quark_widgets.dart';

import '../support/pump.dart';

/// The event form: every field reports its change, the caller's errors show,
/// and the actions call back.
final _draft = CalendarEventDraft(
  title: 'Piano lesson',
  start: DateTime(2026, 9, 17, 16),
  end: DateTime(2026, 9, 17, 17),
);

class _Harness {
  CalendarEventDraft? changed;
  var saves = 0;
  var cancels = 0;
  var deletes = 0;

  Widget editor({
    CalendarEventDraft? draft,
    bool isNew = false,
    bool withDelete = true,
    bool editsSeries = false,
    bool isSaving = false,
    bool canSave = true,
    String? timeError,
    String? saveError,
  }) => CalendarEventEditor(
    draft: draft ?? _draft,
    isNew: isNew,
    editsSeries: editsSeries,
    isSaving: isSaving,
    timeError: timeError,
    saveError: saveError,
    onChanged: (d) => changed = d,
    onSave: canSave ? () => saves++ : null,
    onCancel: () => cancels++,
    onDelete: withDelete ? () => deletes++ : null,
  );
}

void main() {
  testBothViewports('shows the draft in its fields', (tester, size) async {
    await pumpAt(tester, _Harness().editor(), size: size);
    expect(find.text('Edit event'), findsOneWidget);
    expect(find.text('Piano lesson'), findsOneWidget);
    expect(find.text('4:00 PM'), findsOneWidget);
    expect(find.text('5:00 PM'), findsOneWidget);
    expect(
      find.text('Shows in Upcoming. Phone alerts coming later.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testBothViewports('typing a title reports the new draft', (
    tester,
    size,
  ) async {
    final h = _Harness();
    await pumpAt(tester, h.editor(), size: size);
    await tester.enterText(find.byKey(const ValueKey('event_title')), 'Piano');
    expect(h.changed?.title, 'Piano');
    expect(h.changed?.start, _draft.start);
  });

  testBothViewports('all day hides the times and reports the switch', (
    tester,
    size,
  ) async {
    final h = _Harness();
    await pumpAt(tester, h.editor(), size: size);
    await tester.tap(find.byKey(const ValueKey('event_all_day')));
    expect(h.changed?.allDay, isTrue);

    await pumpAt(tester, h.editor(draft: h.changed), size: size);
    expect(find.byKey(const ValueKey('event_start_time')), findsNothing);
    expect(find.byKey(const ValueKey('event_end_time')), findsNothing);
    expect(find.byKey(const ValueKey('event_remind_900')), findsOneWidget);
    expect(find.text('Day before, 9 AM'), findsOneWidget);
  });

  testBothViewports('repeat, reminder and color report their picks', (
    tester,
    size,
  ) async {
    final h = _Harness();
    await pumpAt(tester, h.editor(), size: size);

    await tester.tap(find.byKey(const ValueKey('event_repeat_weekly')));
    expect(h.changed?.repeat, CalendarRepeat.weekly);

    final remind = find.byKey(const ValueKey('event_remind_15'));
    await tester.ensureVisible(remind);
    await tester.tap(remind);
    expect(h.changed?.reminderMinutes, 15);

    final color = find.byKey(const ValueKey('event_color_3'));
    await tester.ensureVisible(color);
    await tester.tap(color);
    expect(h.changed?.colorIndex, 3);
  });

  testBothViewports('turning a reminder off clears it', (tester, size) async {
    final h = _Harness();
    await pumpAt(
      tester,
      h.editor(draft: _draft.copyWith(reminderMinutes: 30)),
      size: size,
    );
    final off = find.byKey(const ValueKey('event_remind_off'));
    await tester.ensureVisible(off);
    await tester.tap(off);
    expect(h.changed, isNotNull);
    expect(h.changed!.reminderMinutes, isNull);
  });

  testBothViewports('keeps a saved reminder it does not offer', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _Harness().editor(draft: _draft.copyWith(reminderMinutes: 1440)),
      size: size,
    );
    expect(find.byKey(const ValueKey('event_remind_1440')), findsOneWidget);
    expect(find.text('1 day before'), findsOneWidget);
  });

  testBothViewports('says a repeating edit reaches every repeat', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _Harness().editor(
        draft: _draft.copyWith(repeat: CalendarRepeat.weekly),
        editsSeries: true,
      ),
      size: size,
    );
    expect(
      find.text('Every week on Thursday. Changes apply to every repeat.'),
      findsOneWidget,
    );
  });

  testBothViewports('shows the errors the caller composed', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _Harness().editor(
        timeError: 'The event has to end after it starts.',
        saveError: "Couldn't save the event.",
      ),
      size: size,
    );
    expect(find.text('The event has to end after it starts.'), findsOneWidget);
    expect(find.text("Couldn't save the event."), findsOneWidget);
  });

  testBothViewports('Save, Cancel, close and Delete call back', (
    tester,
    size,
  ) async {
    final h = _Harness();
    await pumpAt(tester, h.editor(), size: size);
    await tester.tap(find.byKey(const ValueKey('event_save')));
    await tester.tap(find.byKey(const ValueKey('event_cancel')));
    await tester.tap(find.byKey(const ValueKey('event_close')));
    await tester.tap(find.byKey(const ValueKey('event_delete')));
    expect((h.saves, h.cancels, h.deletes), (1, 2, 1));
  });

  testBothViewports('a new event has no Delete', (tester, size) async {
    await pumpAt(
      tester,
      _Harness().editor(isNew: true, withDelete: false),
      size: size,
    );
    expect(find.text('New event'), findsOneWidget);
    expect(find.byKey(const ValueKey('event_delete')), findsNothing);
  });

  testBothViewports('waits while saving', (tester, size) async {
    final h = _Harness();
    await pumpAt(tester, h.editor(isSaving: true), size: size);
    expect(find.byType(QuarkLoader), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('event_save')));
    await tester.tap(find.byKey(const ValueKey('event_cancel')));
    expect((h.saves, h.cancels), (0, 0));
  });

  testBothViewports('Save waits for a draft the caller can save', (
    tester,
    size,
  ) async {
    final h = _Harness();
    await pumpAt(tester, h.editor(canSave: false), size: size);
    await tester.tap(find.byKey(const ValueKey('event_save')));
    expect(h.saves, 0);
  });
}
