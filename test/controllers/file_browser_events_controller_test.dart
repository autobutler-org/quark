import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quark/controllers/file_browser_events_controller.dart';
import 'package:quark/services/events_service.dart';

/// #2763: every listing event anywhere refreshed every open Files page, one
/// refresh per file of an upload.
void main() {
  late StreamController<FileEvent> events;
  late FakeClock clock;
  late int refreshes;
  late String folder;
  late bool busy;
  late FileBrowserEventsController controller;

  setUp(() {
    events = StreamController<FileEvent>.broadcast();
    clock = FakeClock();
    refreshes = 0;
    folder = '/groups/family';
    busy = false;
    controller = FileBrowserEventsController(
      events: events.stream,
      currentFolder: () => folder,
      isBusy: () => busy,
      onRefresh: () => refreshes++,
      quiet: const Duration(seconds: 2),
      maxWait: const Duration(seconds: 10),
      now: clock.now,
      timer: clock.timer,
    );
  });

  tearDown(() {
    controller.dispose();
    events.close();
  });

  FileEvent upload(String path) => FileEvent(kind: 'upload', path: path);

  test('a burst in the open folder costs one refresh', () async {
    for (var i = 0; i < 500; i++) {
      events.add(upload('groups/family'));
    }
    await pumpEventQueue();
    expect(refreshes, 0, reason: 'waits for the burst to end');

    clock.elapse(const Duration(seconds: 2));
    expect(refreshes, 1);

    clock.elapse(const Duration(seconds: 30));
    expect(refreshes, 1);
  });

  test('events elsewhere refresh nothing', () async {
    events
      ..add(upload('groups/everyone'))
      ..add(const FileEvent(kind: 'job_progress', path: ''));
    await pumpEventQueue();
    clock.elapse(const Duration(seconds: 30));
    expect(refreshes, 0);
  });

  test('the folder is read when the event arrives', () async {
    folder = '/groups/everyone';
    events.add(upload('groups/everyone'));
    await pumpEventQueue();
    clock.elapse(const Duration(seconds: 2));
    expect(refreshes, 1);
  });

  test('a steady stream still refreshes once per max wait', () async {
    for (var s = 0; s < 25; s++) {
      events.add(upload('groups/family'));
      await pumpEventQueue();
      clock.elapse(const Duration(seconds: 1));
    }
    expect(refreshes, 2, reason: 'at 10 s and 20 s');

    clock.elapse(const Duration(seconds: 2));
    expect(refreshes, 3, reason: 'and once after the stream stops');
  });

  test('a resync refreshes at once, wherever the folder is', () async {
    events.add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();
    expect(refreshes, 1);
  });

  test('a resync refreshes at once and takes a pending one with it', () async {
    events.add(upload('groups/family'));
    await pumpEventQueue();
    events.add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();
    expect(refreshes, 1);

    clock.elapse(const Duration(seconds: 30));
    expect(refreshes, 1);
  });

  test('nothing refreshes while the page is busy uploading', () async {
    busy = true;
    events
      ..add(upload('groups/family'))
      ..add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();
    clock.elapse(const Duration(seconds: 30));
    expect(refreshes, 0);
  });

  test('a disposed controller refreshes nothing', () async {
    events.add(upload('groups/family'));
    await pumpEventQueue();
    controller.dispose();
    clock.elapse(const Duration(seconds: 30));
    events.add(const FileEvent(kind: 'resync', path: ''));
    await pumpEventQueue();
    expect(refreshes, 0);
  });
}

/// A clock the test moves by hand, firing the timers it made as their time
/// comes.
class FakeClock {
  DateTime _now = DateTime(2026);
  final _timers = <FakeTimer>[];

  DateTime now() => _now;

  Timer timer(Duration duration, void Function() callback) {
    final timer = FakeTimer(_now.add(duration), callback);
    _timers.add(timer);
    return timer;
  }

  /// Moves time on by [duration], firing each timer that falls due in order.
  void elapse(Duration duration) {
    final end = _now.add(duration);
    while (true) {
      final due =
          _timers.where((t) => t.isActive && !t.due.isAfter(end)).toList()
            ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final next = due.first;
      _now = next.due;
      next.fire();
    }
    _now = end;
    _timers.removeWhere((t) => !t.isActive);
  }
}

/// A one-shot timer that fires when [FakeClock] says so.
class FakeTimer implements Timer {
  FakeTimer(this.due, this._callback);

  final DateTime due;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}
