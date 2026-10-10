import 'dart:ui' show SemanticsAction;

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
    String? repeatError,
    String? saveError,
  }) => CalendarEventEditor(
    draft: draft ?? _draft,
    isNew: isNew,
    editsSeries: editsSeries,
    isSaving: isSaving,
    timeError: timeError,
    repeatError: repeatError,
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

  // #2889: the title field is named "Title" whether or not it holds one. Its
  // hint goes quiet once there is a title, which left an edit's field with
  // nothing for a screen reader to call it.
  for (final isNew in [true, false]) {
    testBothViewports(
      'names the title field when ${isNew ? 'new' : 'editing'}',
      (tester, size) async {
        final handle = tester.ensureSemantics();
        final draft = isNew ? _draft.copyWith(title: '') : _draft;
        await pumpAt(
          tester,
          _Harness().editor(draft: draft, isNew: isNew),
          size: size,
        );
        final data = tester
            .getSemantics(
              find.descendant(
                of: find.byKey(const ValueKey('event_title')),
                matching: find.byType(EditableText),
              ),
            )
            .getSemanticsData();
        expect(data.flagsCollection.isTextField, isTrue);
        // A new event's empty field still reads its hint after the name.
        expect(data.label, isNew ? 'Title\nAdd a title' : 'Title');
        expect(data.value, draft.title);
        handle.dispose();
      },
    );
  }

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

  // #2522: an all-day reminder's time of day is picked per event.
  final allDay = CalendarEventDraft.allDayOn(DateTime(2026, 9, 17));

  testBothViewports('an all-day event with no reminder has no time button', (
    tester,
    size,
  ) async {
    await pumpAt(tester, _Harness().editor(draft: allDay), size: size);
    expect(find.byKey(const ValueKey('event_remind_-540')), findsOneWidget);
    expect(find.byKey(const ValueKey('event_remind_900')), findsOneWidget);
    expect(find.byKey(const ValueKey('event_remind_time')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('a timed event has no reminder time button', (
    tester,
    size,
  ) async {
    await pumpAt(
      tester,
      _Harness().editor(draft: _draft.copyWith(reminderMinutes: 15)),
      size: size,
    );
    expect(find.byKey(const ValueKey('event_remind_time')), findsNothing);
  });

  testBothViewports('an all-day reminder shows its saved time of day', (
    tester,
    size,
  ) async {
    // The day before at 2:30 PM.
    final h = _Harness();
    await pumpAt(
      tester,
      h.editor(draft: allDay.copyWith(reminderMinutes: 570)),
      size: size,
    );
    expect(find.text('Day before, 2:30 PM'), findsOneWidget);
    expect(find.text('On the day, 2:30 PM'), findsOneWidget);
    expect(find.byKey(const ValueKey('event_remind_1440')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('event_remind_time')),
        matching: find.text('2:30 PM'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // Switching the day keeps the time.
    final onTheDay = find.byKey(const ValueKey('event_remind_-870'));
    await tester.ensureVisible(onTheDay);
    await tester.tap(onTheDay);
    expect(h.changed?.reminderMinutes, -870);
  });

  testBothViewports('picking a reminder time keeps its day', (
    tester,
    size,
  ) async {
    final h = _Harness();
    await pumpAt(
      tester,
      h.editor(draft: allDay.copyWith(reminderMinutes: 900)),
      size: size,
    );
    final time = find.byKey(const ValueKey('event_remind_time'));
    await tester.ensureVisible(time);
    await tester.tap(time);
    await tester.pumpAndSettle();
    // The picker opens on the saved 9:00 AM; switching to PM makes it 9 PM
    // the day before.
    await tester.tap(find.text('PM'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(h.changed?.reminderMinutes, 180);
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

  testBothViewports('a one-off event has no repeat end', (tester, size) async {
    await pumpAt(tester, _Harness().editor(), size: size);
    expect(find.text('Repeat ends'), findsNothing);
    expect(find.byKey(const ValueKey('event_repeat_ends_on')), findsNothing);
  });

  testBothViewports('a repeating event can end on a date, or never', (
    tester,
    size,
  ) async {
    final h = _Harness();
    final weekly = _draft.copyWith(repeat: CalendarRepeat.weekly);
    await pumpAt(tester, h.editor(draft: weekly), size: size);
    expect(find.text('Repeat ends'), findsOneWidget);
    expect(find.byKey(const ValueKey('event_repeat_until')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('event_repeat_ends_on')));
    // On a date starts a month after the first occurrence.
    expect(h.changed?.repeatUntil, DateTime(2026, 10, 17));
    expect(h.changed?.repeat, CalendarRepeat.weekly);

    await pumpAt(tester, h.editor(draft: h.changed), size: size);
    expect(find.byKey(const ValueKey('event_repeat_until')), findsOneWidget);
    expect(
      find.text('Every week on Thursday until Oct 17, 2026.'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('event_repeat_ends_never')));
    expect(h.changed?.repeatUntil, isNull);
    expect(tester.takeException(), isNull);
  });

  testBothViewports('the repeat end opens a date picker from its value', (
    tester,
    size,
  ) async {
    final h = _Harness();
    final ending = _draft.copyWith(
      repeat: CalendarRepeat.daily,
      repeatUntil: DateTime(2026, 9, 30),
    );
    await pumpAt(tester, h.editor(draft: ending), size: size);
    await tester.ensureVisible(
      find.byKey(const ValueKey('event_repeat_until')),
    );
    await tester.tap(find.byKey(const ValueKey('event_repeat_until')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.tap(find.text('25'));
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(h.changed?.repeatUntil, DateTime(2026, 9, 25));
  });

  testBothViewports('shows the repeat end error the caller composed', (
    tester,
    size,
  ) async {
    final early = _draft.copyWith(
      repeat: CalendarRepeat.weekly,
      repeatUntil: DateTime(2026, 9, 1),
    );
    await pumpAt(
      tester,
      _Harness().editor(draft: early, repeatError: 'Too early.'),
      size: size,
    );
    expect(find.text('Too early.'), findsOneWidget);
  });

  testLargeText('the repeat end fits at large text', (tester, size) async {
    final ending = _draft.copyWith(
      repeat: CalendarRepeat.monthly,
      repeatUntil: DateTime(2027, 9, 17),
    );
    await pumpAt(
      tester,
      _Harness().editor(draft: ending, repeatError: 'Too early.'),
      size: size,
    );
    expect(tester.takeException(), isNull);
    expectNoClippedText(tester);
  });

  testBothViewports('the repeat end meets the tap target guidelines', (
    tester,
    size,
  ) async {
    final ending = _draft.copyWith(
      repeat: CalendarRepeat.weekly,
      repeatUntil: DateTime(2026, 12, 17),
    );
    await pumpAt(tester, _Harness().editor(draft: ending), size: size);
    final handle = tester.ensureSemantics();
    final until = tester.getSemantics(
      find.byKey(const ValueKey('event_repeat_until')),
    );
    expect(until.label, startsWith('Last repeat, '));
    expect(until.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(until.rect.height, greaterThanOrEqualTo(48));
    handle.dispose();
    await expectTapTargetGuidelines(tester);
  });

  testBothViewports('meets the tap target guidelines', (tester, size) async {
    await pumpAt(tester, _Harness().editor(), size: size);
    final handle = tester.ensureSemantics();

    // The switch is named, and the pickers can be pressed by a screen
    // reader, not only announced (#2603).
    expect(
      tester.getSemantics(find.byKey(const ValueKey('event_all_day'))).label,
      'All day',
    );
    final start = tester.getSemantics(
      find.byKey(const ValueKey('event_start_date')),
    );
    expect(start.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
    expect(start.rect.height, greaterThanOrEqualTo(48));
    handle.dispose();
    await expectTapTargetGuidelines(tester);
  });
}
