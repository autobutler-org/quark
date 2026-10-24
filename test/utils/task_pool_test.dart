import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/utils/task_pool.dart';

void main() {
  test('runs every item', () async {
    final done = <int>[];
    final pool = TaskPool<int>(
      concurrency: 3,
      worker: (item) async => done.add(item),
    );

    [1, 2, 3, 4, 5].forEach(pool.add);
    await pool.drain();

    expect(done, unorderedEquals([1, 2, 3, 4, 5]));
  });

  test('holds the concurrency ceiling', () async {
    var inFlight = 0;
    var peak = 0;
    final gates = <Completer<void>>[];
    final pool = TaskPool<int>(
      concurrency: 2,
      worker: (_) async {
        inFlight++;
        peak = peak > inFlight ? peak : inFlight;
        final gate = Completer<void>();
        gates.add(gate);
        await gate.future;
        inFlight--;
      },
    );

    List.generate(10, (i) => i).forEach(pool.add);
    final draining = pool.drain();

    await pumpEventQueue();
    expect(peak, 2, reason: 'both workers busy');

    while (gates.length < 10 || gates.any((g) => !g.isCompleted)) {
      for (final gate in List.of(gates)) {
        if (!gate.isCompleted) gate.complete();
      }
      await pumpEventQueue();
    }
    await draining;

    expect(peak, 2, reason: 'never more than the ceiling, start to finish');
    expect(gates, hasLength(10));
  });

  test('a slow item does not hold the others behind it', () async {
    // The reason for a shared queue rather than fixed batches: a batch runs at
    // the speed of its slowest member.
    final slow = Completer<void>();
    final done = <String>[];
    final pool = TaskPool<String>(
      concurrency: 2,
      worker: (item) async {
        if (item == 'slow') await slow.future;
        done.add(item);
      },
    );

    ['slow', 'a', 'b', 'c'].forEach(pool.add);
    final draining = pool.drain();
    await pumpEventQueue();

    expect(done, containsAll(['a', 'b', 'c']));
    expect(done, isNot(contains('slow')));

    slow.complete();
    await draining;
    expect(done, hasLength(4));
  });

  test('picks up items added while draining', () async {
    final done = <int>[];
    late final TaskPool<int> pool;
    pool = TaskPool<int>(
      concurrency: 2,
      worker: (item) async {
        done.add(item);
        if (item == 1) {
          pool.add(99);
        }
      },
    );

    pool.add(1);
    await pool.drain();

    expect(done, containsAll([1, 99]), reason: 'the same run took it');
  });

  test('drain during a drain joins it rather than starting another', () async {
    var starts = 0;
    final gate = Completer<void>();
    final pool = TaskPool<int>(
      concurrency: 1,
      worker: (_) async {
        starts++;
        await gate.future;
      },
    );

    [1, 2].forEach(pool.add);
    final first = pool.drain();
    final second = pool.drain();

    expect(identical(first, second), isTrue);

    gate.complete();
    await first;
    expect(starts, 2, reason: 'each item ran once, not twice');
  });

  test('keeps going past a failure, then rethrows the first one', () async {
    final done = <int>[];
    final pool = TaskPool<int>(
      concurrency: 2,
      worker: (item) async {
        if (item == 2) throw StateError('item 2 is bad');
        if (item == 3) throw StateError('item 3 is also bad');
        done.add(item);
      },
    );

    [1, 2, 3, 4].forEach(pool.add);

    // One bad item must not strand the queue — but the caller still hears
    // about it rather than the failure vanishing.
    await expectLater(
      pool.drain(),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('item 2'),
        ),
      ),
    );
    expect(done, unorderedEquals([1, 4]));
  });

  test('is reusable after a failed run', () async {
    var attempt = 0;
    final pool = TaskPool<int>(
      concurrency: 1,
      worker: (_) async {
        attempt++;
        if (attempt == 1) throw StateError('first attempt fails');
      },
    );

    pool.add(1);
    await expectLater(pool.drain(), throwsStateError);

    // The failed run must not leave the pool wedged as "still draining".
    pool.add(2);
    await pool.drain();
    expect(attempt, 2);
  });

  test('draining an empty pool is a no-op', () async {
    final pool = TaskPool<int>(concurrency: 2, worker: (_) async {});

    await pool.drain();

    // And it still works afterwards — the empty run must not leave a stale
    // future behind that later drains would return instead of running.
    var ran = 0;
    final worked = TaskPool<int>(concurrency: 2, worker: (_) async => ran++);
    await worked.drain();
    worked.add(1);
    await worked.drain();
    expect(ran, 1);
  });

  test('clear drops what has not started and ends the drain', () async {
    final started = <int>[];
    final gate = Completer<void>();
    late final TaskPool<int> pool;
    pool = TaskPool<int>(
      concurrency: 2,
      worker: (item) async {
        started.add(item);
        await gate.future;
      },
    );

    List.generate(10, (i) => i).forEach(pool.add);
    final draining = pool.drain();
    await pumpEventQueue();

    expect(started, hasLength(2), reason: 'two in flight, eight queued');
    expect(pool.clear(), 8);

    // The two in flight are not interrupted, but nothing new starts.
    gate.complete();
    await draining;

    expect(started, hasLength(2));
  });

  test('rejects a nonsensical concurrency', () {
    expect(
      () => TaskPool<int>(concurrency: 0, worker: (_) async {}),
      throwsA(isA<AssertionError>()),
    );
  });
}
