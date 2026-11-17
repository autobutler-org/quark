import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/auto_save_scheduler.dart';

/// #4110: auto-save holds while an editor asks whether to leave.
void main() {
  const delay = Duration(seconds: 2);

  testWidgets('fires once, a delay after the last edit', (tester) async {
    var fired = 0;
    final scheduler = AutoSaveScheduler(delay: delay, onFire: () => fired++);
    addTearDown(scheduler.dispose);
    scheduler.schedule();
    await tester.pump(const Duration(seconds: 1));
    scheduler.schedule();
    await tester.pump(const Duration(seconds: 1));
    expect(fired, 0);
    await tester.pump(const Duration(seconds: 1));
    expect(fired, 1);
  });

  testWidgets('holds while asking, and resumes on stay', (tester) async {
    var fired = 0;
    final scheduler = AutoSaveScheduler(delay: delay, onFire: () => fired++);
    addTearDown(scheduler.dispose);
    final answer = Completer<bool>();
    scheduler.schedule();
    final leave = scheduler.confirmLeave(
      isDirty: () => true,
      ask: () => answer.future,
    );
    await tester.pump();
    expect(scheduler.isHeld, isTrue);
    // An edit while held starts nothing.
    scheduler.schedule();
    await tester.pump(const Duration(seconds: 5));
    expect(fired, 0);

    answer.complete(false);
    expect(await leave, isFalse);
    expect(scheduler.isHeld, isFalse);
    await tester.pump(delay);
    expect(fired, 1);
  });

  testWidgets('does not resume when told not to, or on leave', (tester) async {
    var fired = 0;
    final scheduler = AutoSaveScheduler(delay: delay, onFire: () => fired++);
    addTearDown(scheduler.dispose);
    scheduler.schedule();
    expect(
      await scheduler.confirmLeave(
        isDirty: () => true,
        ask: () async => false,
        resume: false,
      ),
      isFalse,
    );
    expect(
      await scheduler.confirmLeave(isDirty: () => true, ask: () async => true),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 5));
    expect(fired, 0);
  });

  testWidgets('waits for a save in flight, then skips the question', (
    tester,
  ) async {
    final scheduler = AutoSaveScheduler(delay: delay, onFire: () {});
    addTearDown(scheduler.dispose);
    final upload = Completer<void>();
    var dirty = true;
    // The save clears the unsaved mark inside what is tracked, as the
    // editors' saves do.
    unawaited(
      scheduler.track(() async {
        await upload.future;
        dirty = false;
      }()),
    );
    var asked = false;
    var settled = false;
    final leave = scheduler
        .confirmLeave(isDirty: () => dirty, ask: () async => asked = true)
        .whenComplete(() => settled = true);
    await tester.pump();
    expect(settled, isFalse);

    upload.complete();
    expect(await leave, isTrue);
    expect(asked, isFalse);
  });

  testWidgets('a failed save in flight still lets the question through', (
    tester,
  ) async {
    final scheduler = AutoSaveScheduler(delay: delay, onFire: () {});
    addTearDown(scheduler.dispose);
    final upload = Completer<void>();
    unawaited(scheduler.track(upload.future).catchError((_) {}));
    final leave = scheduler.confirmLeave(
      isDirty: () => true,
      ask: () async => true,
    );
    upload.completeError(Exception('offline'));
    expect(await leave, isTrue);
  });
}
